# nginx_monitor_for_falcon
# open falcon针对nginx监控的shell实现版
## 一、简要说明

小米开源的的open falcon监控系统针对nginx监控的shell实现版本，根据nginx的日志文件，利用awk/sort等shell命令运算获取结果，无需nginx编译支持lua。

[官方提供的为lua实现版本](http://book.open-falcon.org/zh_0_2/usage/ngx_metric.html)  
官方版本源代码  [github地址](https://github.com/GuyCheung/falcon-ngx_metric)


### 1、已实现功能

*	query_count
*	error_count
*	error_rate
*	latency{50,75,95,99}th

*上述字段含义，详见原项目*

### 2、部分实现

*	uri的长度截取

	*目前仅支持一级目录，例如/123;/456等。*

### 3、暂未实现

*	nginx的status
	
	*nginx的status页面上报和监控已经在zabbix实现，所以此处暂不实现*
	
*	upstream_contacts
*	upstream_latency_{50,75,95,99}th

	*upstream未实现的原因，其一考虑到后端的upstream已有监控，其二现有latency几乎和upstream相差无几，所以暂未实现*


### 4、扩展功能

*	针对域名进行扩展，统计的类型为域名+api，原版本未说明是否支持按域名分类

## 二、部署和使用

### 1、使用需求

*	环境

	centos7+nginx+open falcon server
	
*	nginx日志格式

	awk需要严格的字段对应，需要按照下面格式进行配置nginx的日志，或者自行调整get_nginx2.awk。 

```

 log_format  main  '$remote_addr - $remote_user [$time_local] "$host" "$request" '
                     '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for" '
                   '"rt=$request_time" "uct=$upstream_connect_time" "uht=$upstream_header_time" "urt=$upstream_response_time"';
```
### 2、下载及安装

### 3、配置

目录内的config.conf包含下列变量，可以自行调整，脚本执行时自动读入变量。

```
##日志
nginx_log="/var/log/nginx/[^te]*log"
##临时文件
temp_sli="/tmp/temp_sli.`date +%Y%m%d-%H%M%S`"
##endpoint
host_name=`hostname`
## open falcon server
falcon_server="falcon.aa.bb.cn"
##发送频率，单位为秒
step=180
##时间戳
timestamp=`date +%s`
```

### 4、crontab部署

示例
`*/3 * * * * /etc/zabbix/scripts/push_nginx_sli_to_falcon2.sh 3`

*crontab定时运行的间隔时间应和传递给脚本参数相同，该数值换算成秒和配置文件中step变量保持一致*

### 5、测试与调试方法

*	修改config.conf内变量
*	手工执行shell脚本，后面加统计周期的参数，示例如下：
	
	`./push_nginx_sli_to_falcon2.sh 30` 计算30分钟前到现在的日志
	`./push_nginx_sli_to_falcon2.sh `   不加参数计算执行当前分钟的日志


### 6、性能

*	性能

约800行/秒，或者万行/13秒。

*	测试样本环境

	*	样本50万行日志
	*	计算耗时约130秒，cpu单核消耗10%左右，
	* 	测试机型腾讯云标准型S1,12核 32G内存，cpu Intel(R) Xeon(R) CPU E5-26xx 2.5G
	


## 三、实现的思路和方法

### 1、get_nginx2.awk对日志进行处理并生成`temp_sli`文件

*	生成域名+一级目录（中间无空格）和耗时共计以空格分割的2个字段的延迟数据；
* 	生成域名+一级目录（中间无空格）和访问总数、成功数、错误数共计3个字段的明细数据，以及按照域名汇总的汇总数据；
*	生成域名+一级目录（中间无空格）和错误类型和次数共计3个字段的明细数据

*	脚本内容

```
#!/bin/awk -f
## log format
## log_format  main  '$remote_addr - $remote_user [$time_local] "$host" "$request" '
##                      '$status $body_bytes_sent "$http_referer" '
##                      '"$http_user_agent" "$http_x_forwarded_for" '
##		      '"rt=$request_time" "uct=$upstream_connect_time" "uht=$upstream_header_time" "urt=$upstream_response_time"';
## example log
## 11.94.24.11 - - [30/Jan/2019:10:24:36 +0800] "k1.b.com" "POST /car/device/flow/upload HTTP/1.1" 200 64 "-" "okhttp/3.4.1" "-" "rt=0.024" "uct=0.001" "uht=0.024" "urt=0.024"
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
``` 

### 2、temp_sli文件示例

```
###延迟数据
"qsurl.abc.def"videoshare 0.002
"qsurl.abc.def"videoshare 0.001
"qsurl.abc.def"videoshare 0.001
"qsurl.abc.def"videoshare 0.001
"www.abc.def"images 0.001
"www.abc.def"/ 0.001
"www.abc.def"/ 0.001
"www.abc.def"/ 0.001
###失败类型及数量数据
"m1c.abc.def"track 499 6
"k.abc.def"track 502 1
"k.abc.def"/ 404 23
"s.abc.def"/ 404 1
###访问数、成功数、失败数数据
"kadj.abc.def"cdcManage 21 21 0
"kadj.abc.def"tripWeb 60 60 0
"s.abc.def"tripWeixin_tiejia 3475 3475 0
"q.abc.def"cdcComment 8 8 0
"q.abc.def"cdcClientReport 14 14 0
###上述访问数汇总
"abc.def"_serv_ 1 1 0
"kadj.abc.def"_serv_ 236 236 0
"www.crazypandacam.com"_serv_ 1 1 0
"www.abc.def"_serv_ 6 6 0
###全部域名访问量汇总数据
"all"_serv_ 47822 47742 80
```

### 3、get_nginx_sli.awk计算延迟数据

*	该文件处理`temp_sli`，计算延迟数据的50/75/95/99等分位数

*	脚本内容

```
#!/bin/awk -f
## example log
##"k1.com"/ 0.02
##"k1s.com"car 0.279
##"k1.com"car 0.014
##"k1s.com"user 39 39 0
##"service.com"/ 6272 6272 0
##"service.com"car 22925 22925 0

{
  name[$1]=$1
  line_end[$1]=NR
  if($1!=aa) {
    line_start[$1]=NR
    aa=$1
  }
  time[NR]=$2
  #print name[$1],time[NR],line_start[$1],line_end[$1]
}END{
  #print "end"
  for(i in name) {
    fifty=int((line_end[i]-line_start[i])*0.5)+line_start[i]
    sevenfive=int((line_end[i]-line_start[i])*0.75)+line_start[i]
    ninefive=int((line_end[i]-line_start[i])*0.95)+line_start[i]
    ninenine=int((line_end[i]-line_start[i])*0.99)+line_start[i]
    #print time[nine],line_start[i],line_end[i]
    #print i,"95%",time[nine]*1000 ,nine,line_start[i],line_end[i]
    print i,time[fifty],time[sevenfive],time[ninefive],time[ninenine]
  }
}
```
### 4、`push_nginx_sli_to_falcon2.sh` 文件

*	读取配置文件config.conf获取必需的配置
*	调用get_nginx2.awk处理数据生成`temp_sli`文件
* 	陆续调用get_nginx_sli.awk获取访问数据、错误数据、延迟数据等等，并发给falcon server

*	脚本内容详见项目
