#!/usr/bin/env bash

# Add /usr/local/bin to path with highest precedence if not there already
if [[ ":$PATH:" != *:"/usr/local/bin":* ]]; then
    export PATH=/usr/local/bin:$PATH
fi

# give us a nice ps1 prompt if we're in a pty
if [[ "$PS1" ]]; then
    COLOR_FILE=/etc/sysconfig/console/color
    if [[ -s ${COLOR_FILE} ]]; then
        COLOR_NAME=$(cat ${COLOR_FILE})

        case ${COLOR_NAME} in
        "white")
            COLOR_CODE="\e[1;37m"
            ;;
        "red")
            COLOR_CODE="\e[1;31m"
            ;;
        "green")
            COLOR_CODE="\e[1;32m"
            ;;
        "yellow")
            COLOR_CODE="\e[1;33m"
            ;;
        "blue")
            COLOR_CODE="\e[1;34m"
            ;;
        "purple")
            COLOR_CODE="\e[1;35m"
            ;;
        "lightblue")
            COLOR_CODE="\e[1;36m"
            ;;
        *)
            # Default color is green
            COLOR_CODE="\e[1;32m"
            ;;
        esac

    else
        # bold green default
        COLOR_CODE="\e[1;32m"
    fi
    export PS1="[\u@\[${COLOR_CODE}\]$(hostname -f)\[\e[0m\] \W]\$ "
fi
