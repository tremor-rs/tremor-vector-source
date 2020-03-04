#!/bin/bash

while true;
do
  ts=`gdate '+%s%N'`
  echo '{"application": "test", "date": ' $ts ', "message": "demo"}' >> input.log
  sleep 1
done
