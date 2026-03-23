#!/bin/bash
set -e
CURRENT_DIR=$(cd "$(dirname "$0")" && pwd)
echo $CURRENT_DIR
# Display help message
if [[ " $* " =~ " --help" ]] || [[ " $* " =~ " -h" ]]; then
    echo "Usage: $(basename $0) [OPTIONS]"
    echo
    echo "This script configures and modifies source files for CADNA integration."
    echo
    echo "Options:"
    echo " -  [D] is the default option" 
    echo
    echo "  exact_momenta[D]   Make output of phase space picker exact numbers"
    echo "                     Applies cadnize_exact_momenta.py to rambo.h"
    echo 
    echo "  exact_momenta_no   Takes into account the accuracy lost during" 
    echo "                     momenta generation."
    echo
    echo "  load_momenta       Load exact momenta from file (experimental)"
    echo "                     Note: Does not work for now"
    echo
    echo "  CPPProcess         Add cout statements for amp_fp after function calls"
    echo "                     Applies cadnize_cppprocess_cout_amp_fp to CPPProcess.cc"
    echo
    echo "  random_seed        Set random seed mode"
    echo "                     Modifies check_sa.cc to use random seed"
    echo
    echo "  original_seed      Set original seed mode"
    echo "                     Modifies check_sa.cc to use original seed"
    echo
    echo "  --help, -h         Display this help message and exit"
    echo
    echo "Examples:"
    echo "  $(basename $0) exact_momenta random_seed"
    echo "  $(basename $0) CPPProcess original_seed"
    echo
    exit 0
fi


args=" $* "

if [[ "$args" =~ (^|[[:space:]])exact_momenta($|[[:space:]]) ]] && \
   [[ "$args" =~ (^|[[:space:]])exact_momenta_no($|[[:space:]]) ]]; then
    echo "Error: Cannot use both exact_momenta and exact_momenta_no simultaneously."
    exit 1
fi

#checks for macOS

if [[ "$(uname)" == "Darwin" ]]; then
    echo "Running on macOS"
    IS_MAC=true
else
    IS_MAC=false
fi


if [ "$IS_MAC" = false ]; then
                  # Change to cudacpp.mk
  #in the line "LIBFLAGS = -L$(LIBDIR) -l$(MG5AMC_COMMONLIB)" append -lcadnaOpenmpCdebug
  #if there is no -lcadnaOpenmpCdebug in the file
  if grep -Fq cadnaOpenmpCdebug ../cudacpp.mk
  then
      echo "cadnaOpenmpCdebug is already in ../cudacpp.mk"
  else
      echo "putting -lcadnaOpenmpCdebug in ../cudacpp.mk"
      sed -i 's/-L$(LIBDIR) -l$(MG5AMC_COMMONLIB)/-L$(LIBDIR) -l$(MG5AMC_COMMONLIB) -lcadnaOpenmpC -fopenmp/g' ../cudacpp.mk
  fi
                # Change to ../makefile
  #in the line "LIBFLAGS = -L$(LIBDIR) -l$(MG5AMC_COMMONLIB)" append -lcadnaOpenmpCdebug
  #if there is no -lcadnaOpenmpCdebug in the file
  #check if ../makefile exists:
  #sed -i 's/LINKLIBS = $(LINK_MADLOOP_LIB) $(LINK_LOOP_LIBS) -L$(LIBDIR) -ldhelas -ldsample -lmodel -lgeneric -lpdf -lcernlib $(llhapdf) -lbias/LINKLIBS = $(LINK_MADLOOP_LIB) $(LINK_LOOP_LIBS) -L$(LIBDIR) -ldhelas -ldsample -lmodel -lgeneric -lpdf -lcernlib $(llhapdf) -lbias -lcadnaOpenmpCdebug/g' ../makefile_original.mk
  if [ -f "../makefile_original.mk" ]
  then
      if grep -Fq cadnaOpenmpCdebug ../makefile_original.mk
      then
          echo "cadnaOpenmpCdebug is already in ../makefile_original.mk"
      else
          echo "putting -lcadnaOpenmpCdebug in ../makefile_original.mk"

          sed -i 's/LINKLIBS = $(LINK_MADLOOP_LIB) $(LINK_LOOP_LIBS) -L\.\.\/\.\.\/lib\/ -ldhelas -ldsample -lmodel -lgeneric -lpdf -lgammaUPC -lcernlib $(llhapdf) -lbias/LINKLIBS = $(LINK_MADLOOP_LIB) $(LINK_LOOP_LIBS) -L..\/..\/lib\/ -ldhelas -ldsample -lmodel -lgeneric -lpdf -lgammaUPC -lcernlib $(llhapdf) -lbias -lcadnaOpenmpC/g' ../makefile_original.mk
      fi
  fi
else
                 # Change to cudacpp.mk
   #in the line "LIBFLAGS = -L$(LIBDIR) -l$(MG5AMC_COMMONLIB)" append -lcadnaOpenmpCdebug
   #if there is no -lcadnaOpenmpCdebug in the file
   if grep -Fq cadnaC ../cudacpp.mk
   then
       echo "cadnaC is already in ../cudacpp.mk"
   else
       echo "putting -lcadnaC in ../cudacpp.mk"
       sed -i 's/-L$(LIBDIR) -l$(MG5AMC_COMMONLIB)/-L$(LIBDIR) -l$(MG5AMC_COMMONLIB) -lcadnaC /g' ../cudacpp.mk
   fi
                 # Change to ../makefile
   #in the line "LIBFLAGS = -L$(LIBDIR) -l$(MG5AMC_COMMONLIB)" append -lcadnaC
   #if there is no -lcadnaC in the file
   #check if ../makefile exists:
   #sed -i 's/LINKLIBS = $(LINK_MADLOOP_LIB) $(LINK_LOOP_LIBS) -L$(LIBDIR) -ldhelas -ldsample -lmodel -lgeneric -lpdf -lcernlib $(llhapdf) -lbias/LINKLIBS = $(LINK_MADLOOP_LIB) $(LINK_LOOP_LIBS) -L$(LIBDIR) -ldhelas -ldsample -lmodel -lgeneric -lpdf -lcernlib $(llhapdf) -lbias -lcadnaC/g' ../makefile_original.mk
   if [ -f "../makefile_original.mk" ]
   then
       if grep -Fq cadnaC ../makefile_original.mk
       then
           echo "cadnaC is already in ../makefile_original.mk"
       else
           echo "putting -lcadnaC in ../makefile_original.mk"

           sed -i 's/LINKLIBS = $(LINK_MADLOOP_LIB) $(LINK_LOOP_LIBS) -L\.\.\/\.\.\/lib\/ -ldhelas -ldsample -lmodel -lgeneric -lpdf -lgammaUPC -lcernlib $(llhapdf) -lbias/LINKLIBS = $(LINK_MADLOOP_LIB) $(LINK_LOOP_LIBS) -L..\/..\/lib\/ -ldhelas -ldsample -lmodel -lgeneric -lpdf -lgammaUPC -lcernlib $(llhapdf) -lbias -lcadnaC/g' ../makefile_original.mk
       fi
   fi
fi

          #add missing definition for operators on custom complex types
if [ -f "../../src/mgOnGpuCxtypes.h" ]
then
    if grep -Fq "CADNA operator overload" ../../src/mgOnGpuCxtypes.h
    then
        echo "CADNA operator overload is already in ../../src/mgOnGpuCxtypes.h"
    else
        echo "putting CADNA operator overload in ../../src/mgOnGpuCxtypes.h"
        echo "skipping this step for now"
       python3 $CURRENT_DIR/srcpy/cadnize_mgOnGpuCxtypes.py ../../src/mgOnGpuCxtypes.h
    fi
else
  echo "../../src/mgOnGpuCxtypes.h does not exist"
fi

          #remove fast math from the cudacpp one folder up
if [ -f "../cudacpp.mk" ]
then
    if grep -Fq "removed for CADNA" ../cudacpp.mk
    then
        echo "fast math already comented out"
    else
        echo "comenting fast math in ../cuda_cpp.mk"
       python3 $CURRENT_DIR/srcpy/cadnize_fast_math.py ../cudacpp.mk
    fi
else
  echo "../cudacpp.mk does not exist"
fi
           #changes in mgOnGpuConfig.h - #include cadna.h, #undef SIMD, typdefs to _st
echo
echo "          cadnize_mgOnGpuConfig.py"
if [ -f "../../src/mgOnGpuConfig.h" ]
then
    python3 $CURRENT_DIR/srcpy/cadnize_mgOnGpuConfig.py ../../src/mgOnGpuConfig.h
fi

           #changes in HelAmps.h - double to fptype to prevent implicit conversion
echo
echo "          cadnize_HelAmps.py"
if [ -f "../../src/HelAmps_sm.h" ]
then
    python3 $CURRENT_DIR/srcpy/cadnize_HelAmps.py ../../src/HelAmps_sm.h
fi

                # move every $(LIBFLAGS)  and $(LINKLIBS) to the end of the line in ../cudacpp.mk and ../makefile
echo
echo "          cadnize_libflags.py"
python3 $CURRENT_DIR/srcpy/cadnize_libflags.py ../cudacpp.mk
#check if ../makefile exists:
if [ -f "../makefile_original.mk" ]
then
    python3 $CURRENT_DIR/srcpy/cadnize_libflags.py ../makefile_original.mk
fi


                #Changes in check_sa.cc and bridge
echo
echo "          cadnize_check_sa.py"
python3 $CURRENT_DIR/srcpy/cadnize_check_sa.py check_sa.cc 0

                #Changes in check_sa.cc and bridge
echo
echo "          cadnize_bridge.py"
python3 $CURRENT_DIR/srcpy/cadnize_bridge.py ../Bridge.h
#TODO check if the bridge in the supprocess individual directory needs to be checked as well


                #repair the constexpr fptype and volatile fptype errors
echo
echo "          cadnize_constexpr_replace.py"
#  loop over list of files
files=(check_sa.cc ../../src/HelAmps_sm.h CPPProcess.cc fsampler.cc MadgraphTest.h testxxx.cc runTest.cc color_sum.cc testmisc.cc)
for file in "${files[@]}"
do
    python3 $CURRENT_DIR/srcpy/cadnize_constexpr_replace.py $file
done


echo
echo "          cadnize_std_replace.py"
files=(../../src/mgOnGpuFptypes.h ../../src/HelAmps_sm.h ../CrossSectionKernels.cc fsampler.cc MadgraphTest.h testxxx.cc runTest.cc)
for file in "${files[@]}"
do
    python3  $CURRENT_DIR/srcpy/cadnize_std_replace.py $file
done

                #paste "\n" after every operator after every "=" in HelAmps_sm.h - make optional
#python3 $CURRENT_DIR/srcpy/cadnize_expand_equations.py ../../src/HelAmps_sm.h

#care for the additional options

                #Make output of phase space picker exact numbers
if [[ ! " $* " =~ " exact_momenta_no" ]]; then
    echo
    echo "          cadnize_exact_momenta.py"
    #python3 $CURRENT_DIR/srcpy/cadnize_exact_momenta.py ../../src/rambo.h
    python3 $CURRENT_DIR/srcpy/cadnize_exact_momenta_main.py ./check_sa.cc
fi

#does not work for now (dont know the contents of the read_momenta.h)
if [[ " $* " =~ " load_momenta" ]]; then
    echo
    echo "         cadnize_load_momenta.py"
    #python3 $CURRENT_DIR/srcpy/cadnize_exact_momenta.py ../../src/rambo.h
    #python3 $CURRENT_DIR/srcpy/cadnize_exact_momenta_main.py  ./check_sa.cc
    #python3 $CURRENT_DIR/srcpy/cadnize_exact_momenta_to_load_momenta.py ../../src/rambo.h $CURRENT_DIR/read_momenta.h
    #python3 $CURRENT_DIR/srcpy/cadnize_exact_momenta_to_load_momenta.py ../../src/rambo.h $CURRENT_DIR/read_momenta.h
    python3 $CURRENT_DIR/srcpy/cadnize_load_momenta_main.py ./check_sa.cc
fi


                #cout every amp_fp after a function call
if [[ " $* " =~ " CPPProcess" ]]; then
    echo
    echo "         cadnize_cppprocess_cout_amp_fp"
    python3 $CURRENT_DIR/srcpy/cadnize_CPPProcess_cout_amp_fp.py CPPProcess.cc
fi

                #set the seed random or original
if [[ " $* " =~ " random_seed" ]]; then
    echo
    echo "         cadnize_seed_change.py random"
    python3 $CURRENT_DIR/srcpy/cadnize_seed_change.py check_sa.cc random
fi

                #set the seed random or original
if [[ " $* " =~ " original_seed" ]]; then
    echo
    echo "         cadnize_seed_change.py original"
    python3 $CURRENT_DIR/srcpy/cadnize_seed_change.py check_sa.cc original
fi

