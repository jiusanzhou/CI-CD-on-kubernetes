#!/usr/bin/env bash

############# Prepare ###############

# Use colors, but only if connected to a terminal, and that terminal
# supports them.
if which tput >/dev/null 2>&1; then
    ncolors=$(tput colors)
fi
if [ -t 1 ] && [ -n "$ncolors" ] && [ "$ncolors" -ge 8 ]; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    BOLD="$(tput bold)"
    NORMAL="$(tput sgr0)"
    END="$(tput sgr0)"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    BOLD=""
    NORMAL=""
    END=""
fi

kernel_name=$(uname -s)

################## Helper #################

# @1: file
# @2: sig
# @3: value
function replace()
{
    [ "$kernel_name" == "Darwin" ] && sed -e "s/$2/$3/g" -i "" $1
    [ "$kernel_name" == "Linux" ] && sed -e "s/$2/$3/g" -i $1
}

function gentoken()
{
    if [ "$kernel_name" == "Darwin" ]; then
        local drone_token=`openssl rand -base64 8 | md5 | head -c8; echo`
    else
        local drone_token=`cat /dev/urandom | env LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1`
    fi
    
    echo `echo $drone_token | base64`
}

function kctl()
{
    kubectl $@ 2> /dev/null
}


################# Start ###################

default_ns="drone"

function usage()
{
    local NAME=$(basename "$0")
    echo "Usage of $NAME:" 
    echo "      $NAME create|install  Install drone on kubernetes."
    echo "                               Please read the README at first."
    echo "      $NAME remove|uninstall  Uninstall drone from kubernetes."
    echo "      $NAME info Show information of drone on kubernetes."
    echo "      $NAME --help"
    exit
}

function checkcluster()
{
    kubectl cluster-info > /dev/null 2>&1
    if [ $? -eq 1 ]
    then
        echo "kubectl was unable to reach your Kubernetes cluster."
        exit 1
    fi
}

function create()
{
    # =============== Step 0 =================
    # Check cluster in local
    checkcluster

    # =============== Step 1 =================
    echo -e "${YELLOW}Install drone on kuberneter cluster ...${END}"

    # =============== Step 2 =================
    read -p "Offer a namespace your want to in drone (default: ${default_ns}): " ns
    if [ -z "${ns// }" ]
    then
      ns=$(echo ${default_ns})
    fi
    echo -e "${GREEN}[✔️]${END} Create namespace: ${GREEN}${ns}${END}"
    replace "namespace.yaml" "REPLACE-THIS-WITH-NAMESAPCE" ${ns}
    for i in `ls *.yaml`; do
        replace $i "REPLACE-THIS-WITH-NAMESAPCE" ${ns}
    done
    kctl create -f namespace.yaml

    echo -e "${YELLOW}Randomly generating secrets and replace...${END}"

    local b64_drone_token=$(gentoken)
    replace "secret.yaml" "REPLACE-THIS-WITH-BASE64-ENCODED-VALUE" ${b64_drone_token}

    # =============== Step 2 =================
    echo -e "${GREEN}[✔️]${END} Apply secret, configmap, deployment and servie${END}"
    kctl create -f secret.yaml
    kctl create -f configmap.yaml
    kctl create -f server-deployment.yaml
    kctl create -f server-service.yaml

    if [ $? -ne 0 ]
    then
        echo -e "${RED}Install drone ends with error. Please checkout the cluster or config."
        return 1
    fi

    # =============== Step 3 =================
    echo "Since this is your first time running this script, we have created a" \
        "front-facing Load Balancer. You'll need to wait" \
        "for the LB to initialize and be assigned a hostname. We'll pause for a" \
        "bit and walk you through this after the break."
    while true; do
        echo "${YELLOW}Waiting for a while for hostname assignment...${END}"
        sleep 10
        echo "[[ Querying your drone-server service to see if it has a hostname yet... ]]"
        echo
        kctl describe svc drone-service --namespace=drone
        echo "[[ Query complete. ]]"
        read -p "Do you see a 'Loadbalancer Ingress' field with a value above? (y/n) " yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) echo "We'll give it some more time.";;
            * ) echo "No idea what that was, but we'll assume yes!";;
        esac
    done

    echo
    echo "Excellent. This will be the hostname that you can create a DNS (CNAME)"
    echo "record for, or point your browser at directly."
    read -p "<Press enter to proceed once you have noted your ELB's hostname>"

    # =============== Done =================echo
    echo "===== Drone Server installed ============================================"
    echo "Your cluster is now downloading the Docker image for Drone Server."
    echo "You can check the progress of this by typing 'kubectl get pods' in another"
    echo "tab. Once you see 1/1 READY for your drone-server-* pod, point your browser"
    echo "at http://<your-elb-hostname-here> and you should see a login page."
    echo
    read -p "<Press enter once you've verified that your Drone Server is up>"
    echo
    echo "===== Drone Agent installation =========================================="
    kctl create -f agent-deployment.yaml
    echo "Your cluster is now downloading the Docker image for Drone Agent."
    echo "You can check the progress of this by typing 'kubectl get pods'"
    echo "Once you see 1/1 READY for your drone-agent-* pod, your Agent is ready"
    echo "to start pulling and running builds."
    echo
    read -p "<Press enter once you've verified that your Drone Agent is up>"
    echo
    echo "===== Post-installation tasks ==========================================="
    echo "At this point, you should have a fully-functional Drone install. If this"
    echo "Is not the case, stop by either of the following for help:"
    echo
    echo "  * Discussion Site, help category: https://discuss.drone.io/"
    echo
    echo "You'll also want to read the documentation: https://docs.drone.io"
    echo "${GREEN}Finished!${END}"
}

function remove()
{
    echo "Remove drone on kubernetes ..."
}

function info()
{
    echo -e "${YELLOW}Show information of drone on kubernetes ...${END}"
}

function main()
{
    case "$1" in
        create|install)
            create ${@:2}
            ;;
        remove|uninstall)
            remove ${@:2}
            ;;
        info)
            info ${@:2}
            ;;
        *)
            usage
            ;;
    esac
        shift
}

main $@
