@echo off

set agent="G:\OmicsWorks\agent\bin\research.exe"

CALL %agent% -r=research.txt -e=expression.csv -a=metabolites.csv -s=sampleinfo.csv -k=./pubmed/ -w=./demo/ -c=config.ini --skip-literature --skip-kb --module 1,2,3,4,6,7,8,9