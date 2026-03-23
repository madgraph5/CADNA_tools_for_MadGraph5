#file from argument:
import sys
import re
if len(sys.argv) > 1:
    fileName = sys.argv[1]
else:
    exit("No file name given")
f = open(fileName, "r")

#read lines
lines = f.readlines()
f.close()
changes = 0

i=0
for l in lines:
    if "double" in l:
        l = re.sub(r'\bdouble\b(?!_st)', 'fptype', l)
        changes += 1
        
        lines[i] = l
    
    i=i+1
print(f"Changes in: {fileName:<30}\t{changes}")
from tempfile import mkstemp
from shutil import move, copymode
from os import fdopen, remove

#replace old file with new file
tempfileName = fileName+"_temp"
f = open(tempfileName, "w")
f.writelines(lines)
f.close()

copymode(fileName, tempfileName)
remove(fileName)
move(tempfileName, fileName)
