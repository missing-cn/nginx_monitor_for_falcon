#!/bin/awk -f
## example log 
##"k1s.a.com"/ 0.02
##"k1.b.com"car 0.279
##"k1.a.com"box 0.014
##"k1.com" 31 31 0
##"k1.com"/ 6272 6272 0
##"k1s.a.com"car 22925 22925 0
#BEGIN{
#}
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
