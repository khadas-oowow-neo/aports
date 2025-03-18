#/bin/sh

#= khadas lib

CMD(){
	echo "# $@"
	"$@"
}

apk(){
    echo "## apk $@">&2
    /sbin/apk "$@"
}

tar(){
    echo "## tar $@">&2
    /usr/bin/tar "$@"
}
