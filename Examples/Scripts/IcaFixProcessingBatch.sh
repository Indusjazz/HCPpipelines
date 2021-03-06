#!/bin/bash

# Global default values
DEFAULT_STUDY_FOLDER="${HOME}/data/Pipelines_ExampleData"
DEFAULT_SUBJECT_LIST="100307"
DEFAULT_ENVIRONMENT_SCRIPT="${HOME}/projects/Pipelines/Examples/Scripts/SetUpHCPPipeline.sh"
DEFAULT_RUN_LOCAL="FALSE"
#DEFAULT_FIXDIR="${HOME}/tools/fix1.06"  ##OPTIONAL: If not set will use $FSL_FIXDIR specified in EnvironmentScript

#
# Function Description
#	Get the command line options for this script
#
# Global Output Variables
#	${StudyFolder}			- Path to folder containing all subjects data in subdirectories named 
#							  for the subject id
#	${Subjlist}				- Space delimited list of subject IDs
#	${EnvironmentScript}	- Script to source to setup pipeline environment
#	${FixDir}				- Directory containing FIX
#	${RunLocal}				- Indication whether to run this processing "locally" i.e. not submit
#							  the processing to a cluster or grid
#
get_options() {
	local scriptName=$(basename ${0})
	local arguments=("$@")

	# initialize global output variables
	StudyFolder="${DEFAULT_STUDY_FOLDER}"
	Subjlist="${DEFAULT_SUBJECT_LIST}"
	EnvironmentScript="${DEFAULT_ENVIRONMENT_SCRIPT}"
	FixDir="${DEFAULT_FIXDIR}"
	RunLocal="${DEFAULT_RUN_LOCAL}"

	# parse arguments
	local index=0
	local numArgs=${#arguments[@]}
	local argument

	while [ ${index} -lt ${numArgs} ]
	do
		argument=${arguments[index]}

		case ${argument} in
			--StudyFolder=*)
				StudyFolder=${argument#*=}
				index=$(( index + 1 ))
				;;
			--Subject=*)
				Subjlist=${argument#*=}
				index=$(( index + 1 ))
				;;
			--EnvironmentScript=*)
				EnvironmentScript=${argument#*=}
				index=$(( index + 1 ))
				;;
			--FixDir=*)
				FixDir=${argument#*=}
				index=$(( index + 1 ))
				;;
			--runlocal | --RunLocal)
				RunLocal="TRUE"
				index=$(( index + 1 ))
				;;
			*)
				echo "ERROR: Unrecognized Option: ${argument}"
				exit 1
				;;
		esac
	done

	# check required parameters
	if [ -z ${StudyFolder} ]
	then
		echo "ERROR: StudyFolder not specified"
		exit 1
	fi

	if [ -z ${Subjlist} ]
	then
		echo "ERROR: Subjlist not specified"
		exit 1
	fi

	if [ -z ${EnvironmentScript} ]
	then
		echo "ERROR: EnvironmentScript not specified"
		exit 1
	fi

	# MPH: Allow FixDir to be empty at this point, so users can take advantage of the FSL_FIXDIR setting
	# already in their EnvironmentScript
#    if [ -z ${FixDir} ]
#    then
#        echo "ERROR: FixDir not specified"
#        exit 1
#    fi

	if [ -z ${RunLocal} ]
	then
		echo "ERROR: RunLocal is an empty string"
		exit 1
	fi

	# report options
	echo "-- ${scriptName}: Specified Command-Line Options: -- Start --"
	echo "   StudyFolder: ${StudyFolder}"
	echo "   Subjlist: ${Subjlist}"
	echo "   EnvironmentScript: ${EnvironmentScript}"
	if [ ! -z ${FixDir} ]; then
		echo "   FixDir: ${FixDir}"
	fi
	echo "   RunLocal: ${RunLocal}"
	echo "-- ${scriptName}: Specified Command-Line Options: -- End --"
}  # get_options()

#
# Function Description
#	Main processing of this script
#
#	Gets user specified command line options and runs a batch of ICA+FIX processing
#
main() {
	# get command line options
	get_options "$@"

	# set up pipeline environment variables and software
	source ${EnvironmentScript}

	# MPH: If DEFAULT_FIXDIR is set, or --FixDir argument was used, then use that to
	# override the setting of FSL_FIXDIR in EnvironmentScript
	if [ ! -z ${FixDir} ]; then
		export FSL_FIXDIR=${FixDir}
	fi

	# set list of fMRI on which to run ICA+FIX
	fMRINames="rfMRI_REST1_LR rfMRI_REST1_RL rfMRI_REST2_LR rfMRI_REST2_RL"

	# If you wish to run "multi-run" (concatenated) FIX, specify the name to give the concatenated output files
	# In this case, all the runs included in ${fMRINames} become the input to multi-run FIX
	# Otherwise, leave ConcatName empty (in which case "single-run" FIX is executed serially on each run in ${fMRINames})
	ConcatName=""
	# ConcatName="rfMRI_REST1_2_LR_RL"  ## Do NOT include spaces!

	# set temporal highpass full-width (2*sigma) to use, in seconds
	bandpass=2000

	# set whether or not to regress motion parameters (24 regressors)
	# out of the data as part of FIX (TRUE or FALSE)
	domot=FALSE
	
	# set training data file
	TrainingData=HCP_hp2000.RData

	# set FIX threshold (controls sensitivity/specificity tradeoff)
	FixThreshold=10
	
	# establish queue for job submission
	QUEUE="-q hcp_priority.q"
	if [ "${RunLocal}" == "TRUE" ]; then
		queuing_command=""
	else
		queuing_command="${FSLDIR}/bin/fsl_sub ${QUEUE}"
	fi

	DIR=$(pwd)
	
	for Subject in ${Subjlist}; do
		echo ${Subject}

		ResultsFolder="${StudyFolder}/${Subject}/MNINonLinear/Results"
		cd ${ResultsFolder}
		
		if [ -z ${ConcatName} ]; then
			# single-run FIX
			FixScript=${HCPPIPEDIR}/ICAFIX/hcp_fix
			
			for fMRIName in ${fMRINames}; do
				echo "  ${fMRIName}"

				InputFile="${fMRIName}/${fMRIName}"

				cmd="${queuing_command} ${FixScript} ${InputFile} ${bandpass} ${domot} ${TrainingData} ${FixThreshold}"
				echo "About to run: ${cmd}"
				${cmd}
			done

		else
			# multi-run FIX
			FixScript=${HCPPIPEDIR}/ICAFIX/hcp_fix_multi_run
			ConcatNameFile="${ConcatName}/${ConcatName}"

			InputFile=""			
			for fMRIName in ${fMRINames}; do
				InputFile+="${fMRIName}/${fMRIName}@"
			done
			
			echo "  InputFile: ${InputFile}"

			cmd="${queuing_command} ${FixScript} ${InputFile} ${bandpass} ${ConcatFileName} ${domot} ${TrainingData} ${FixThreshold}"
			echo "About to run: ${cmd}"
			${cmd}

		fi

		cd ${DIR}

	done
}  # main()

#
# Invoke the main function to get things started
#
main $@

