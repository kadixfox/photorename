#!/bin/bash
# ---------------------------------------------------------------------------
# photorename - rename photos/videos in current directory to unique,
# informative names based on camera model / time taken / shutter count /
#focal length / shutter speed / aperture

# Copyright 2024,  <kadixfox>

# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

# Usage:
# photorename [-h|--help] [-c|--copy] [-s|--symlink] [-d|--directory] [-r|--recursive] [-n|--dryrun] [-o|--output] [-f|--file] [-p|--preserve-tree]

# Revision history:
# 2024-01-16	Allow specifying output file name when running recursively and preserving tree
#		Allow choosing a copy (cp) or a symlink (ln -s) over a move (mv)
#		Prevent recursing into output dir
#		Various code and formatting fixes
# 2024-01-04	Created by new_script ver. 3.3
# ---------------------------------------------------------------------------

PROGNAME=${0##*/}
VERSION="0.1"

# pre-exit housekeeping
clean_up() {
	return
}

error_exit() {
	printf -- "${PROGNAME}: ${1:-"Unknown Error"}\n" >&2
	clean_up
	exit 1
}

graceful_exit() {
	clean_up
	exit
}

# handle trapped signals
signal_exit() {
	case $1 in
		INT)
			error_exit "Program interrupted by user" ;;
		TERM)
			printf -- "\n$PROGNAME: Program terminated\n" >&2
			graceful_exit ;;
		*)
			error_exit "$PROGNAME: Terminating on unknown signal" ;;
	esac
}

usage() {
	printf -- "Usage: $PROGNAME [-h|--help] [-c|--copy] [-s|--symlink] [-d|--directory] [-r|--recursive] [-n|--dryrun] [-o|--output] [-f|--file] [-p|--preserve-tree]\n\n"
}

help_message() {
	cat <<- _EOF_
$PROGNAME ver. $VERSION
rename photos/videos in current directory to unique, informative names based on camera model / time taken / shutter count / focal length / shutter speed / aperture

`usage`
  Options:
  -h, --help  Display this help message and exit
  -c, --copy  Copy files to output rather than move, not possible with -s
  -s, --symlink  Symlink files to output rather than move, not possible with -c
  -d, --directory  Directory to find files in; defaults to current directory
  -r, --recursive  Recurse subdirectories to find files
  -n, --dryrun Print proposed changed without applying
  -o, --output  Directory to move renamed files; defaults to current directory
  -f, --file  Operate on a single file
  -p, --preserve-tree  Preserve output directories of input files when operating recursively; exclusive to -r

	_EOF_
	return
}

testdir(){
	if ls $1 >/dev/null; then
		:
	else
		printf -- "\n"
		error_exit "File or Directory specified: '$1' does not exist"
	fi
}

# trap signals
trap "signal_exit TERM" TERM HUP
trap "signal_exit INT"  INT



# parse command-line
while [[ -n $1 ]]; do
	case $1 in
		-h | --help)
			help_message; graceful_exit ;;
		-c | --copy)
			copy=1 ;;
		-s | --symlink)
			if [[ $copy ]]; then
				usage
				error_exit "--symlink cannot be used with --copy and vice versa"
			else
				symlink=1
			fi ;;
		-d | --directory)
			directory="$2"
			testdir "$directory"
			shift ;;
		-r | --recursive)
			recursive=1 ;;
		-n | --dryrun)
			dryrun=1 ;;
		-o | --output)
			output="$2"
			presout="$output"
			testdir "$output"
			shift ;;
		-f | --file)
			if [[ -z $2 ]]; then
				usage
				error_exit "No file specified for option $1"
			else
				nocount=1
				file="$2"
				testdir "$file"
			fi
			shift ;;
		-p | --preserve-tree)
			if [[ $recursive ]]; then
				preservetree=1
			else
				usage
				error_exit "--preserve-tree exclusive to --recursive"
			fi ;;
		*)
			usage
			error_exit "Unknown option $1" ;; 
	esac
	shift
done

# functions and constants
if [[ -z $directory ]]; then
	directory=.
fi

if [[ -z $output ]]; then
	output=.
	presout=.
fi

desiredtags=(model datetimeoriginal shuttercount focallength shutterspeed aperture filetypeextension)

genflags(){
	for tag in ${desiredtags[@]}; do
		printf -- "-$tag "
	done
}

genfilename(){
	for tag in ${returnedtags[@]}; do
		if [ $tag == "filetypeextension" ]; then
			printf -- ".${!tag}"
		else
			printf -- "${!tag}_"
		fi
	done
}

dooperation(){
	if [[ $copy ]]; then
		cp -vi "./`realpath --relative-to=. \"$file\"`" "./`realpath --relative-to=. \"$output/$(genfilename)\"`"
	elif [[ $symlink ]]; then
		ln -svi "`readlink -f \"$file\"`" "./`realpath --relative-to=. \"$output/$(genfilename)\"`"
	else
		mv -vi "./`realpath --relative-to=. \"$file\"`" "./`realpath --relative-to=. \"$output/$(genfilename)\"`"
	fi
}

tryrename(){
	if [[ $preservetree ]]; then
		output=$presout/`dirname "$file"`
	fi
	if [[ $dryrun ]]; then
		printf -- "'$file' -> '$output/`genfilename`'\n"
	else
		mkdir -p "$output"
		dooperation
	fi
}

tryrecurse(){
	if [[ $file ]]; then
		printf -- "$file"
	elif [[ $recursive ]]; then
		find "$directory" -type f -not -path "./`realpath --relative-to=. \"$output\"`/*"
	else
		find "$directory" -maxdepth 1 -type f
	fi
}

gettags(){
	exiftool -Q -S $flags "$file"
}

seqtags(){
	seq 0 ${#tagsarr[@]}
}

evaltags(){
	case ${tagsarr[$tag]} in
		Model:*)
			model=`awk '{print $2"_"$3}' <<<${tagsarr[$tag]}`
			returnedtags+=(model) ;;
		DateTimeOriginal:*)
			datetimeoriginal=`sed -e 's/:/./g' <<<${tagsarr[$tag]} | awk '{print $2"-"$3}'`
			returnedtags+=(datetimeoriginal) ;;
		ShutterCount:*)
			shuttercount=`awk '{print $2}' <<<${tagsarr[$tag]}`
			returnedtags+=(shuttercount) ;;
		FocalLength:*)
			focallength=`awk '{print $2$3}' <<<${tagsarr[$tag]}`
			returnedtags+=(focallength) ;;
		ShutterSpeed:*)
			shutterspeed=`sed -e 's/\//-/g' <<<${tagsarr[$tag]} | awk '{print $2"s"}'`
			returnedtags+=(shutterspeed) ;;
		Aperture:*)
			aperture=`awk '{print "f-"$2}' <<<${tagsarr[$tag]}`
			returnedtags+=(aperture) ;;
		FileTypeExtension:*)
			filetypeextension=`awk '{print $2}' <<<${tagsarr[$tag]}`
			returnedtags+=(filetypeextension) ;;
	esac
}

evalreturnedtags(){
	if [[ ${returnedtags[@]} == *shuttercount* ]]; then
		returnedtags=("${returnedtags[@]/datetimeoriginal}")
		tryrename
	elif [[ ${returnedtags[@]} == *datetimeoriginal* ]]; then
		if [[ ${#datetimeoriginal} == 19 ]]; then
			tryrename
		else
			failed+="\n$file"
		fi
	else
		failed+="\n$file"
	fi
}


if [[ $dryrun ]]; then
	printf  -- "Performing DRY RUN! No files will be modified!\n\n"
fi

flags=`genflags`

if [[ -z $nocount ]]; then
	numfiles=`tryrecurse | wc -l`
else
	numfiles=1
fi

# do the thing
printf -- "Processing $numfiles files\n\n"

filenum=0

oldifs=$IFS
IFS=$'\n'
for file in `tryrecurse`; do
	filenum=$((filenum+1))
	printf "\r%s" "[$filenum/$numfiles] $((filenum*100/numfiles))% "
	IFS=$oldifs

	tags=`gettags`

	IFS=$'\n'
	tagsarr=($tags)
	IFS=$oldifs

	returnedtags=()

	for tag in `seqtags`; do
		evaltags
	done
	
	evalreturnedtags
done
if [[ -z $failed ]]; then
	graceful_exit
else
	error_exit "Failed to create unique names for the following files:\n$failed"
fi
