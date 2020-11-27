#!/bin/sh

Help=no
Reinstall=no
Verbose=no
Quiet=no

set -e

while [ ${#} -gt 0 ]
do
	Arg=${1}
	shift 1
	case ${Arg} in
	"-h"|"--help")
		Help=yes
		;;
	"-q"|"--quiet")
		Quiet=yes
		;;
	"-r"|"--reinstall")
		Reinstall=yes
		;;
	"-v"|"--verbose")
		Verbose=yes
		;;
	*)
		echo "Bad argument: ${Arg}"
		return 20
	esac
done

if [ "${Help}" = "yes" ]
then
	echo
	echo "YourPrompt> ${0} [-r|--reinstall] [-v|--verbose]"
	echo "YourPrompt> ${0} <-h|--help>"
	echo
	echo "Options:"
	echo "  -h, --help      = Display this output."
	echo "  -q, --quiet     = Suppress renewal messages. (No news is good news.)"
	echo "  -r, --reinstall = Reinstall existing certificates."
	echo "  -v, --verbose   = Don't suppress boring output."
	echo
	return 0
fi

. /usr/local/etc/dehydrated/config
if [ ! -d "${BASEDIR}" ]
then
	echo "Creating base directory for Dehydrated."
	mkdir "${BASEDIR}"
fi

if [ ! -d "${BASEDIR}/accounts" ]
then
	echo
	echo "To use Let's Encrypt you must agree to their Subscriber Agreement,"
	echo "which is linked from:"
	echo
	echo "    https://letsencrypt.org/repository/"
	echo
	echo -n "Do you accept the Let's Encrypt Subscriber Agreement (y/n)? "
	read yes
	case $yes in
		y|Y|yes|YES|Yes|yup)
			break 2
			;;
		*)
			echo "OK, tls-setup.sh will be aborted."
			return 30
	esac
	/usr/local/bin/dehydrated --register --accept-terms
fi

if [ ! -d "${WELLKNOWN}" ]
then
	echo "Creating well-known directory for Let's Encrypt challenges."
	mkdir -p "${WELLKNOWN}"
fi

/usr/local/bin/nfsn list-aliases >${BASEDIR}/domains.txt

if [ ! -s "${BASEDIR}/domains.txt" ]
then
	echo "There are no aliases for this site."
	return 10
fi

for Alias in `cat "${BASEDIR}/domains.txt"`
do
	if [ -d "/home/public/${Alias}" ]
	then
		AliasWellKnown="/home/public/${Alias}/.well-known"
		if [ -h "${AliasWellKnown}" ]
		then
			echo "Upgrading ${AliasWellKnown}"
			rm "${AliasWellKnown}"
		fi
		if [ ! -d "${AliasWellKnown}" ]
		then
			echo "Creating .well-known directory for ${Alias}."
			mkdir "${AliasWellKnown}"
			ACMEChallenge="${AliasWellKnown}/acme-challenge"
			if [ ! -h "${ACMEChallenge}" ]
			then
				if [ -e "${ACMEChallenge}" ]
				then
					echo "Please remove existing ${ACMEChallenge} to use this script." >&2
					return 40
				fi
				echo "Linking acme-challenge for ${Alias}."
				ln -s ../../.well-known/acme-challenge ${ACMEChallenge}
			fi
		fi
	fi
	if [ "${Reinstall}" = "yes" ]
	then
		cat \
			"${BASEDIR}/certs/${Alias}/cert.pem" \
			"${BASEDIR}/certs/${Alias}/chain.pem" \
			"${BASEDIR}/certs/${Alias}/privkey.pem" \
		| /usr/local/bin/nfsn -i set-tls
	fi
done

if [ "${Reinstall}" = "yes" ]
then
	return 0
fi

/usr/local/bin/dehydrated --cron >${BASEDIR}/dehydrated.out

cp ${BASEDIR}/dehydrated.out ${BASEDIR}/dehydrated.check
if [ "${Verbose}" = "no" ]
then
	mv ${BASEDIR}/dehydrated.check ${BASEDIR}/dehydrated.checkin
	fgrep -v INFO: ${BASEDIR}/dehydrated.checkin | fgrep -v unchanged | fgrep -v 'Skipping renew' | fgrep -v 'Reusing account from' | fgrep -v 'Certificate will not expire' | fgrep -v 'Creating chain cache directory' | fgrep -v 'Checking expire date' | fgrep -v 'Running automatic cleanup' | egrep -v '^Processing' | cat >${BASEDIR}/dehydrated.check
	if [ "${Quiet}" = "yes" ]
	then
		mv ${BASEDIR}/dehydrated.check ${BASEDIR}/dehydrated.checkin
		fgrep -v 'Moving unused file to archive directory' ${BASEDIR}/dehydrated.checkin | fgrep -v 'Certificate will expire (Less than 30 days). Renewing!' | egrep -v '^ \+ (Signing|Generating|Requesting|Received|Handling|Deploying|Checking|Cleaning|Responding|Creating|Installing) ' | fgrep -v 'Challenge is valid!' |  fgrep -v 'pending challenge(s)' | fgrep -v 'Done!' | fgrep -v 'OK: Setup was fully confirmed.' | egrep -v '^e[0-9]+: OK \(' | cat >${BASEDIR}/dehydrated.check
	fi
fi
[ -f ${BASEDIR}/dehydrated.checkin ] && rm -f ${BASEDIR}/dehydrated.checkin

if [ "`cat ${BASEDIR}/dehydrated.check`" != "" -o "${Verbose}" = "yes" ]
then
	cat "${BASEDIR}/dehydrated.out"
fi

if ! /usr/local/bin/nfsn test-cron tlssetup | fgrep -q 'exists=true'
then
	echo Adding scheduled task to renew certificates.
	if [ "${Verbose}" = "no" ]
	then
		if [ "${Quiet}" = "yes" ]
		then
			/usr/local/bin/nfsn add-cron tlssetup "/usr/local/bin/tls-setup.sh -q" me ssh '?' '*' '*'
		else
			/usr/local/bin/nfsn add-cron tlssetup /usr/local/bin/tls-setup.sh me ssh '?' '*' '*'
		fi
	else
		/usr/local/bin/nfsn add-cron tlssetup "/usr/local/bin/tls-setup.sh -v" me ssh '?' '*' '*'
	fi
fi

exit 0

