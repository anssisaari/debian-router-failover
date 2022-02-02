#!/bin/bash
# failover.sh
# v2.0 2022-01-16
# Alex Alexander <alex.alexander@gmail.com>

# Your main internet interface
if [ -n "$IF_WAN" ] ; then
	IF_MAIN=$IF_WAN
else
	IF_MAIN=enp1s0
fi

# The interface you want to enable if IF_MAIN is not working
if [ -n "$IF_LTE" ] ; then
        IF_FAILOVER=$IF_LTE
else
	IF_FAILOVER=wwan0
fi

# the metric to set the FAILOVER to when disabled
METRIC_FAILOVER_OFF="99999"
# the metric to set the FAILOVER to when ENABLED
METRIC_FAILOVER_ACTIVE="10"

# this number of pings has to fail for us to change state
FAILOVER_PING_THRESHOLD=2

# the hosts we ping to figure out if internet is alive.
# order matters, so we check two separate providers to make sure it's not the other end
HOSTS_TO_PING=(
  "1.1.1.1"
  "8.8.8.8"
  "1.0.0.1"
  "8.8.4.4"
)

# how long to waiting when testing main interface
PING_WAIT_MAIN=2
# how long to waiting when testing failover interface
PING_WAIT_FAILOVER=5
PING_LOOPS=1

# how often should we check
CHECK_MAIN_INTERVAL=10

# check whether IF_FAILOVER is working every X seconds
CHECK_FAILOVER_INTERVAL=600
# also check on start
CHECK_FAILOVER_COUNTER=${CHECK_FAILOVER_INTERVAL}
# my failover if is a little unstable, so when checking if it is working, we check twice
CHECK_FAILOVER_THRESHOLD=1
CHECK_FAILOVER_ROUTE=0
CHECK_FAILOVER_PING=0

DEBUG=false
if [[ "$1" == "-d" ]]; then
  DEBUG=true
fi

# did we fail because the route was missing?
FAILOVER_DUE_TO_MISSING_ROUTE=false

LAST_STATE=
FAILOVER=false
PINGS_FAILED=0
PINGS_PASSED=0

# We use this method to update some external service.
function update_ha() {
  echo "New State: ${@}"

  # 
  # echo "Sending state to Home Assistant: ${@}"
  # curl --header "Content-Type: application/json" \
  #  --request POST -o /dev/null -s \
  #  --data "{\"state\": \"${@^}\"}" \
  #  http://<some-host>/api/webhook/failover-status >/dev/null

  LAST_STATE="${@}"
}

# This function knows how to check if pings work over an interface.
# It exports results to PINGS_PASSED and PINGS_FAILED
function check_pings() {
  IF_TYPE=${1} # MAIN, FAILOVER
  IF_NAME="IF_${IF_TYPE}"
  IF=${!IF_NAME}
  if [[ -z ${IF} ]]; then
    echo "[EEE] Could not deduct IF from ${IF_TYPE}"
    exit 1
  fi
  PING_WAIT_NAME="PING_WAIT_${IF_TYPE}"
  PING_WAIT=${!PING_WAIT_NAME}
  PINGS_FAILED=0
  PINGS_PASSED=0
  for ip in "${HOSTS_TO_PING[@]}"; do
    ping -c ${PING_LOOPS} -W ${PING_WAIT} -I ${IF} "${ip}" 2>&1 >/dev/null
    PING_RESULT=$?
    if [[ ${PING_RESULT} -eq 0 ]]; then
      PINGS_PASSED=$(( PINGS_PASSED + 1 ))
      PINGS_FAILED=0
      if [[ "${FAILOVER}" == true ]] || [[ "${DEBUG}" == true ]]; then
        echo "[I] (failover: ${FAILOVER}) CHECKING ${IF_TYPE} IF: Ping to ${ip}/${IF} succeeded!"
      fi
    else
      PINGS_PASSED=0
      PINGS_FAILED=$(( PINGS_FAILED + 1 ))
      echo "[E] (failover: ${FAILOVER}) CHECKING ${IF_TYPE} IF: Ping to ${ip}/${IF} FAILED"
    fi
    [[ ${PINGS_PASSED} -ge ${FAILOVER_PING_THRESHOLD} ]] && break
    [[ ${PINGS_FAILED} -ge ${FAILOVER_PING_THRESHOLD} ]] && break
  done
}

# Our main check function
function check() {
  # first, check if our main interface route even exists
  # if not, we can't really do anything, but we can update our state
  if ! ip route list | grep default | grep -q ${IF_MAIN}; then
    if [[ "${FAILOVER_DUE_TO_MISSING_ROUTE}" == false ]]; then
      echo "[E] Could not find route for main interface (${IF_MAIN})"
      FAILOVER_DUE_TO_MISSING_ROUTE=1
      update_ha "Active (no route)"
    fi
    return
  fi
  
  # then, check if our failover interface route even exists
  # we can't failover if there's no failover route ;)
  # this is cheap, so we do it every time
  if ! ip route list | grep default | grep -q ${IF_FAILOVER}; then
    if [[ ${CHECK_FAILOVER_ROUTE} -lt ${CHECK_FAILOVER_THRESHOLD} ]]; then
      echo "[W] Could not find route for failover interface, will retry (${IF_FAILOVER})"
      CHECK_FAILOVER_ROUTE=$(( CHECK_FAILOVER_ROUTE + 1 )) 
      return
    fi
    echo "[E] Could not find route for failover interface (${IF_FAILOVER})"
    update_ha "Unavailable (no route)"
    return
  fi

  CHECK_FAILOVER_ROUTE=0

  CHECK_FAILOVER_COUNTER=$(( CHECK_FAILOVER_COUNTER + CHECK_MAIN_INTERVAL ))
  CHECK_FAILOVER_WAS_DONE=false
  # every ~10m, send some pings over the failover interface to make sure it's
  # actually working. If it's not, we can't do much to fix it automatically,
  # but at least we can send out a notification to investigate, so we are not
  # surprised later!
  if [[ ${CHECK_FAILOVER_COUNTER} -ge ${CHECK_FAILOVER_INTERVAL} ]]; then
    echo "Verifying Failover Internet is reachable"

    check_pings FAILOVER

    if [[ ${PINGS_FAILED} -ge ${FAILOVER_PING_THRESHOLD} ]]; then
      if [[ ${CHECK_FAILOVER_PING} -lt ${CHECK_FAILOVER_THRESHOLD} ]]; then
        echo "[W] Failover interface check pings failed, will retry (${IF_FAILOVER})"
        CHECK_FAILOVER_PING=$(( CHECK_FAILOVER_PING + 1 )) 
        return
      fi
      update_ha "Unavailable (no ping)"
      return
    else
      CHECK_FAILOVER_COUNTER=0
    fi
    CHECK_FAILOVER_WAS_DONE=true
  fi

  CHECK_FAILOVER_PING=0

  STATE=

  ip_route_list=$(ip route list | grep "^default" | grep "${IF_FAILOVER}")
  METRIC=$(ip route list | grep "^default" | grep "${IF_FAILOVER}" | sed "s:.*metric \([0-9]*\).*:\1:")
  if [[ "${DEBUG}" == true ]] 
  then
    echo "(Metric debug) ip route list for wwan0 is: $ip_route_list"
    echo "(Metric debug) METRIC is $METRIC"
  fi
  [[ ${METRIC} -eq ${METRIC_FAILOVER_OFF} ]] &&
    FAILOVER=false || FAILOVER=true
  if [[ "${FAILOVER}" == true ]]; then
    DEFAULT_GW=$(ip route list | grep "^default" | grep "${IF_MAIN}" | sed "s:.*via \([.0-9]*\).*:\1:")
    VIA="via ${DEFAULT_GW}"
  else
    VIA=""
  fi

  # we made it here, all routes seem to be present, let's check our main interface
  check_pings MAIN

  if [[ ${PINGS_FAILED} -lt ${FAILOVER_PING_THRESHOLD} ]]; then
    STATE="Ready"
    if [[ "${FAILOVER}" == true ]]; then
      echo "[CHANGE] Ping through main IF {$IF_MAIN} worked, RESTORING"
      # we need to re-write the route so it lowers the metric
      FAILOVER_GW=$(ip route list | grep "^default" | grep "${IF_FAILOVER}" | sed "s:.*via \([.0-9]*\).*:\1:")
      ip route del default via ${FAILOVER_GW}
      ip route add default via ${FAILOVER_GW} dev ${IF_FAILOVER} metric ${METRIC_FAILOVER_OFF}
      FAILOVER_DUE_TO_MISSING_ROUTE=0
    fi
    if [[ "${FAILOVER_DUE_TO_MISSING_ROUTE}" == true ]]; then
      echo "[CHANGE] Main IF ${IF_MAIN} route came back, RESTORING"
      FAILOVER_DUE_TO_MISSING_ROUTE=0
    fi
  else
    STATE="Active (no ping)"
    if [[ "${FAILOVER}" == true ]]; then
      [[ "${DEBUG}" == true ]] &&
        echo "(failover: true) Pings failed, but we've already failed over."
    else
      echo "[CHANGE] At least ${FAILOVER_PING_THRESHOLD} pings failed in a row, FAILING OVER"
      # we need to re-write the route so it lowers the metric
      FAILOVER_GW=$(ip route list | grep "^default" | grep "${IF_FAILOVER}" | sed "s:.*via \([.0-9]*\).*:\1:")
      ip route del default via ${FAILOVER_GW}
      ip route add default via ${FAILOVER_GW} dev ${IF_FAILOVER} metric ${METRIC_FAILOVER_ACTIVE}
    fi
  fi

  if [[ ${STATE} != ${LAST_STATE} ]] || [[ "${CHECK_FAILOVER_WAS_DONE}" == true ]]; then
     update_ha "${STATE}"
  fi
}

echo "Internet Failover Script"
echo "---"
echo "Main Interface: ${IF_MAIN}"
echo "-   Main Check: ${CHECK_MAIN_INTERVAL}s"
echo "Failover Interface: ${IF_FAILOVER}"
echo "-   Failover Check: ${CHECK_FAILOVER_INTERVAL}s"
echo "==="

while true; do
  check
  sleep ${CHECK_MAIN_INTERVAL}
done
