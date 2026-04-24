#This script should be copied into the Subprocess folder and automatically run the promise analysis on the subprocess
#Prequiments are: generated process and results in gdb_run_output_float-03_1.out file

# -------------------------------
# Step 1: Creating the boilerplate
# -------------------------------

import os
import re
import shutil
import srcpy.momnetumParser as mpr

CADNA_TOOLBOX_PATH = os.environ.get(
    "CADNA_TOOLBOX_PATH",
    "/path/to/cadna/toolbox"
)

PROMISE_TOOLBOX_PATH = os.environ.get(
    "PROMISE_TOOLBOX_PATH",
    "/path/to/cadna/toolbox"
)

def numberOfBadMomenta(subprocess_dir, precision_threshold = 3):
    if os.path.exists("gdb_run_output_float-O3_1.out"):
        f = open( "gdb_run_output_float-O3_1.out", 'r')
    else:
        print("No file gdb_run_output_float-O3_1.out")
        return 0

    matrix_element = []
    matrixElementPrecision = []
    matrixElementPrecisionZeros = 0
    momentum = []
    momentaPrecision = []

    print("Got here")
    # parse the file
    matrixElementPrecisionZeros = mpr.parse_file(f, momentum, momentaPrecision, matrix_element, matrixElementPrecision,
                                                 matrixElementPrecisionZeros)
    count = 0
    for prec in matrixElementPrecision:
        if prec < precision_threshold:
            count += 1

#    count += matrixElementPrecisionZeros
    print("Count is" + str(count))
    return count

def numberOfBadMomenta_native(num_lines=100):
    if os.path.exists("gdb_run_output_float-O3_1.out"):
       filepath="gdb_run_output_float-O3_1.out"
    else:
        print("No file gdb_run_output_float-O3_1.out")
        return 0


    pattern = re.compile(r'Momenta: for event (\d+) \(\d+\)')
    
    try:
        with open(filepath, 'rb') as f:
            # Seek to end
            f.seek(0, 2)
            file_size = int(f.tell())
            
            estimated_bytes = num_lines * 80
            start_pos = max(0, file_size - estimated_bytes)
            f.seek(start_pos)
            
            content = f.read().decode('utf-8', errors='ignore')
            lines = content.split('\n')
            
            for line in reversed(lines):
                match = pattern.search(line)
                if match:
                    return int(match.group(1))
                #else:
                    #return numberOfBadMomenta_native(1000)
                    
    except (FileNotFoundError, IOError) as e:
        print(f"Error reading {filepath}: {e}")
        return None
    
    return None

def change_nevt_main(nevt):
    with open("main.cpp", "r") as f:
        lines = f.readlines()
    with open("main.cpp", "w") as f:
        for line in lines:
            if "int nevt = " in line:
                line = "    int nevt = " + str(nevt) + ";\n"
            f.write(line)

    f.close()

# create dir and cd
# TODO: make a env. var.
CADNA_toolbox_path = CADNA_TOOLBOX_PATH + "/boiler_plate"
PROMISE_env_path = PROMISE_TOOLBOX_PATH
Current_path = os.getcwd()
os.makedirs(Current_path + "/boiler_plate", exist_ok=True)
os.chdir(Current_path + "/boiler_plate")
# Update Current_path to the new working directory
Current_path = os.getcwd()

#copy from toolbox
print(" 1) Copying files from toolbox:")
COPY_FILES = ["CMakeLists.txt", "main.cpp", "make_boilerplate.sh", "promise.yml", "src"]
for file in COPY_FILES:
    #print(file)
    src = os.path.join(CADNA_toolbox_path, file)
    dst = os.path.join(Current_path, file)
    
    # Remove destination if it exists to avoid copytree errors
    if os.path.exists(dst):
        if os.path.isdir(dst):
            shutil.rmtree(dst)
        else:
            os.remove(dst)
            
    if os.path.isdir(src):
        shutil.copytree(src, dst)
    else:
        shutil.copy2(src, dst)

FILES_SRC = ["CPPProcess.cc", "CPPProcess.h", "HelAmps_sm.h", "color_sum.h", "color_sum.cc"]
FILES_SRC_BCKP = ["HelAmps_sm_bckp", "CPPProcess_bckp"]
FILES_BOILER = ["Parameters_sm.cc", "Parameters_sm.h"]
FILES_CARDS = ["param_card.dat"]
FILES_MAIN = ["gdb_run_output_float-03_1.out"]

#check for old files and remove
print(" 2) Removing old files:")
for f in FILES_SRC:
    if os.path.exists("src/" + f):
        #print("Removing src/" + f)
        os.remove("src/" + f)
for f in FILES_SRC_BCKP:
    if os.path.exists("src/" + f):
        #print("Removing src/" + f)
        os.remove("src/" + f)
for f in FILES_BOILER:
    if os.path.exists("src/boilerplate/" + f):
        #print("Removing src/boilerplate" + f)
        os.remove("src/boilerplate/" + f)
for f in FILES_CARDS:
    if os.path.exists("src/Cards/" + f):
        #print("Removing Cards/" + f)
        os.remove("src/Cards/" + f)
for f in FILES_MAIN:
    if os.path.exists(f):
        #print("Removing from main" + f)
        os.remove(f)

#copy the new files
print(" 3) Copying new files")
shutil.copy2("../../../src/Parameters_sm.h", "src/boilerplate")
shutil.copy2("../../../src/Parameters_sm.cc", "src/boilerplate")
shutil.copy2("../../../Cards/param_card.dat", "src/Cards")
shutil.copy2("../gdb_run_output_float-O3_1.out", Current_path)
shutil.copy2("../../../src/HelAmps_sm.h", "src")
shutil.copy2('../color_sum.cc', 'src')
shutil.copy2('../../color_sum.h', 'src')
shutil.copy2('../CPPProcess.cc', 'src')
shutil.copy2('../CPPProcess.h', 'src')

#make boilerplate
print(" 4) Making boilerplate")
os.system("./make_boilerplate.sh")

#promises HelAmps_sm.h
print(" 5) Promises HelAmps_sm.h")
os.chdir(Current_path+"/src")
os.system("python3 promisesHelAmps.py > /dev/null 2>&1")
os.chdir(Current_path)

print(" 6) Setting number of bad momenta")
#nb = numberOfBadMomenta(Current_path)
nb = numberOfBadMomenta_native()
print("Number of bad momenta: " + str(nb))
change_nevt_main(nb)

#source promise enviroment
print(" 6) Running promise")
os.system("source " + PROMISE_env_path +".venv/bin/activate")
os.system("promise --precs=sd --nbDigits=3 --verbosity=1")


