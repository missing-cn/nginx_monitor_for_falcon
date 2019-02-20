#!/bin/sh
cur_time=`date +%H:%M:%S`
counter=0
run_dir=$(cd "$(dirname "$0")";pwd)
if [ -f $run_dir/config.conf ] ; then
  source $run_dir/config.conf
else
  echo "config file not found." && exit
fi
if [  $1 ] ; then
  time_dur=$1
  ago_time=`date -d "$time_dur minutes ago" +%H:%M:%S`
else
  ago_time=$cur_time
fi
function prepare() {
  awk -v start=$ago_time -v end=$cur_time -f $run_dir/get_nginx2.awk $nginx_log > $temp_sli
}
function send_to_falcon() {
  if [ "$#" -ge 7 ] ; then 
    metric=$1
    endpoint=$2
    timestamp=$3
    step=$4
    value=$5
    domain=$6
    api=$7
    if [ $8 ] ; then
      errcode=$8
      curl -X POST -d '[{"metric": "'"${metric}"'", "endpoint": "'"${endpoint}"'", "timestamp": '$timestamp', "step": '$step', "value": '$value', "counterType": "GAUGE", "tags": "domain='"${domain}"',api='"${api}"',errcode='"${errcode}"'"}]' http://$falcon_server:1988/v1/push && let counter+=1 && echo -e " $counter"
    else
      curl -X POST -d '[{"metric": "'"${metric}"'", "endpoint": "'"${endpoint}"'", "timestamp": '$timestamp', "step": '$step', "value": '$value', "counterType": "GAUGE", "tags": "domain='"${domain}"',api='"${api}"'"}]' http://$falcon_server:1988/v1/push && let counter+=1 && echo -e " $counter"
    fi
  #echo -e "\n metric:$metric endpoint:$endpoint timestamp:$timestamp step:$step value:$value domain:$domain api:$api" 
  else
    echo "parameter error! send to falcon must have 7/8 parameters. but current is $# ."
    echo "$@"
  fi
}
function send_latency() {
  if [ "$#" -eq 6 ] ; then
    latency_50=$3
    latency_75=$4
    latency_95=$5
    latency_99=$6
    for i in latency_50th latency_75th latency_95th latency_99th
      do
        case $i in
          latency_50th)
                       value=$latency_50
                       ;;
          latency_75th)
                       value=$latency_75
                       ;;
          latency_95th)
                       value=$latency_95
                       ;;
          latency_99th)
                       value=$latency_99
                       ;;
        esac
        send_to_falcon $i $host_name $timestamp $step $value $domain $api
      done
  else
    echo "send_latency error. $@"
  fi
}
# 发送所有api的总数、成功数、失败数
function send_api() {
  awk '{if(NF==4)print $0}' $temp_sli |while read name all suc err
  do
    domain=`echo $name|awk -F'"' '{print $2}'|sed 's/"//g'`
    api=`echo $name |awk -F'"' '{print $3}'`
    #error_rate=`echo $err  $all |awk '{print $1/$2}'`
    send_to_falcon "query_count" $host_name $timestamp $step $suc $domain $api
    if [ "$err" -gt 0 ] ;then 
      error_rate=`echo $err  $all |awk '{print $1/$2}'`
      send_to_falcon "error_count" $host_name $timestamp $step $err $domain $api
      send_to_falcon "error_rate"  $host_name $timestamp $step $error_rate $domain $api
    fi
  done
}
# 发送各api的错误类型(500/501/503)等等的明细数据
function send_api_err() {
  awk '{if(NF==3)print $0}' $temp_sli |while read name errcode err
  do
    domain=`echo $name|awk -F'"' '{print $2}'|sed 's/"//g'`
    api=`echo $name |awk -F'"' '{print $3}'`
    send_to_falcon "error_count" $host_name $timestamp $step $err $domain $api $errcode
  done
}
# 发送50/75/95/99分位的明细数据
function send_latency_detail() {
  awk '{if(NF==2)print $0}' $temp_sli |sort -k1,1 -k2n,2|awk -f $run_dir/get_nginx_sli.awk | while read name fifty sevenfive ninefive ninenine
  do
    domain=`echo $name|awk -F'"' '{print $2}'|sed 's/"//g'`
    api=`echo $name |awk -F'"' '{print $3}'`
    send_latency $domain $api  $fifty $sevenfive $ninefive $ninenine
  done
}
function send_latency_by_domain() {
  awk '{if(NF==2){split($1,a,"\"");print a[2],$2}}' $temp_sli |sort -k1,1 -k3n,3 |awk -f $run_dir/get_nginx_sli.awk | while read name  latency_50 latency_75 latency_95 latency_99 
  do 
    domain=$name
    api="_serv_"
    send_latency $domain $api  $latency_50 $latency_75 $latency_95 $latency_99
  done
}
function send_latency_total() {
  awk '{if(NF==2)print "all", $2}' $temp_sli |sort -n |awk -f $run_dir/get_nginx_sli.awk | while  read name  latency_50 latency_75 latency_95 latency_99
  do
    domain="all"
    api="_serv_"
    send_latency $domain $api  $latency_50 $latency_75 $latency_95 $latency_99
  done
}
prepare && echo "prepare done."
send_api && echo "sent api done."
send_api_err && echo "sent api error done." 
send_latency_detail && echo "sent  detail  of api latency done."
send_latency_by_domain && echo "sent  latency by domain latency done."
send_latency_total && echo "sent latency of total done."
rm -f $temp_sli
