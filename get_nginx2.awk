#!/bin/awk -f
## log format
## log_format  main  '$remote_addr - $remote_user [$time_local] "$host" "$request" '
##                      '$status $body_bytes_sent "$http_referer" '
##                      '"$http_user_agent" "$http_x_forwarded_for" '
##		      '"rt=$request_time" "uct=$upstream_connect_time" "uht=$upstream_header_time" "urt=$upstream_response_time"';
## example log 
## 11.94.24.11 - - [30/Jan/2019:10:24:36 +0800] "k1s.com" "POST /car/device/flow HTTP/1.1" 200 64 "-" "okhttp/3.4.1" "-" "rt=0.024" "uct=0.001" "uht=0.024" "urt=0.024"
## FPAT="([^ ]+)|(\"[^\"]+\")" 将log 字段设置为空格或者以""包含起来的字符分割
BEGIN{
  FPAT="([^ ]+)|(\"[^\"]+\")"
}
{
  if((substr($4,14,8)>=start)&&(substr($4,14,8)<=end)) {
    # $7 为request,计算出其中的一级目录作为api
    split($7,a," ")
    api_length=split(a[2],b,"/")
    if((api_length==2)||(b[1]==b[2])) {
      b[2]="/"
    }
  
    api[$6,b[2]]=b[2]
    cnt[$6,b[2]]+=1
    if($8>=400) {
      api_err[$6,b[2],$8]+=1
    }
    else {
      api_suc[$6,b[2]]+=1
      split($15,c,"=")
      rt[$6,b[2]]=substr(c[2],1,length(c[2])-1)+0
      #忽略耗时为0的记录
      if(rt[$6,b[2]]==0) {
        next
      } 
      else {
        print $6b[2],rt[$6,b[2]]
      }
    }
  }
} END {
  # 列出所有一级目录的总量、成功访问量、失败量
  #print "list"  
  for(i in api) {
    split(i,j,SUBSEP);
    print j[1]j[2] ,cnt[i]+0,api_suc[i]+0,cnt[i]-api_suc[i]
    all[j[1],"_serv_"]=j[1]"_serv_"
    cnt[j[1],"_serv_"]+=cnt[j[1],j[2]]
    api_suc[j[1],"_serv_"]+=api_suc[j[1],j[2]]
    #api_err[j[1],"_serv_"]+=api_err[j[1],j[2]]
    #print all[j[1],"_serv_"],cnt[j[1],"_serv_"],api_suc[j[1],"_serv_"],api_err[j[1],"_serv_"]
  }
  for(x in api_err) {
    split(x,y,SUBSEP);
    print y[1]y[2],y[3] ,api_err[y[1],y[2],y[3]]
    #api_err[y[1],y[2],y[3]]+=api_err[y[1],y[2],y[3]]
    #api_err[j[1],j[2],"_serv_"]+=api_err[j[1],j[2],j[3]] 
  }
  ##列出所有以域名为类别的总量 
  #print "total"
  for(l in all) {
    split(l,k,SUBSEP)
    print k[1]k[2] ,cnt[l]+0,api_suc[l]+0,cnt[l]-api_suc[l]
    #统计所有域名之和
    all_cnt+=cnt[l]
    all_api_suc+=api_suc[l]
  }
  #列出全部域名的统计
   print "\"all\"_serv_",all_cnt,all_api_suc,all_cnt-all_api_suc
}
 
