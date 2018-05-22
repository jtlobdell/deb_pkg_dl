#!/bin/bash

args_invalid=true

# recursive calls
if [ "$#" -eq 4 ]; then
    orig_pkg=$1
    pkg=$2
    rel=$3
    arch=$4
    args_invalid=false
fi

# normal calls
if [ "$#" -eq 3 ]; then
    orig_pkg=$1
    pkg=$1
    rel=$2
    arch=$3
    args_invalid=false
fi

if [ args_invalid == true ]; then
    echo "Usage: $0 package release architecture"
    exit
fi

tmpdir=~/.cache/deb_pkg_dl
depsdir=$tmpdir/dependencies
detsdir=$tmpdir/details
dlpagedir=$tmpdir/dlpage
dpkgdir=$tmpdir/dpkg
pkg_ignore=( libc6 gcc-4.9-base debconf dpkg coreutils debianutils zlib1g multiarch-support libgcc1 passwd libpam-modules libpam-modules-bin libpam0g libglib libsemanage lsb-base)
mkdir -p $tmpdir
mkdir -p $depsdir
mkdir -p $detsdir
mkdir -p $dlpagedir
mkdir -p $dpkgdir/$orig_pkg

# don't repeat packages
do_dl=true
if [ -f $detsdir/$pkg ]; then
    if [ $pkg == $orig_pkg ]; then
        do_dl=false
    else
        exit
    fi
fi

# determine dependencies for this package
if [ $do_dl == true ]; then
    curl --silent https://packages.debian.org/$rel/$pkg > $detsdir/$pkg
fi
cat $detsdir/$pkg | grep -A 1 --no-group-separator "dep:" | \
grep -v "dep:" | sed 's/^[[:space:]]*//' | sed 's/<[^>]*>//g' | \
uniq > $depsdir/$pkg

# add dependencies to dependencies of original package
if [ $pkg != $orig_pkg ]; then
    cat $depsdir/$pkg >> $depsdir/$orig_pkg
fi

# remove duplicates
sort -u -o $depsdir/$orig_pkg $depsdir/$orig_pkg

# remove ignored packages
for i in "${pkg_ignore[@]}"
do
    sed -i "/$i/d" $depsdir/$orig_pkg
done

packages=( $(cat $depsdir/$orig_pkg) )
for p in "${packages[@]}"
do
    ./$0 $orig_pkg $p $rel $arch
done

if [ $orig_pkg != $pkg ]; then
    # not the original caller; quit
    exit
fi

# determined all the dependencies, now get them
all_deps=( $(cat $depsdir/$orig_pkg) )
for d in "${all_deps[@]}"
do
    # determine which architecture to dl
    is_arch=$(cat $detsdir/$d | grep href | grep download | grep $arch | wc -l)
    is_all=$(cat $detsdir/$d | grep href | grep download | grep all | wc -l)
    if [ ! -f $dlpagedir/$d ]; then
        if [ $is_arch == "1" ]; then
            curl --silent https://packages.debian.org/$rel/$arch/$d/download > $dlpagedir/$d
        elif [ $is_all == "1" ]; then
            curl --silent https://packages.debian.org/$rel/all/$d/download > $dlpagedir/$d
        fi
    fi
    # determine which link it is
    do_dl=true
    if [ $(cat $dlpagedir/$d | grep "href=\"http://security.debian.org/debian-security" | wc -l) == "1" ]; then
        dllink=$(cat $dlpagedir/$d | grep "href=\"http://security.debian.org/debian-security" | sed 's/^[[:space:]]*//' | sed 's/^.*<a href="//' | sed 's/">.*//')
    elif [ $(cat $dlpagedir/$d | grep "ftp.us.debian.org/debian" | wc -l) == "1" ]; then
        dllink=$(cat $dlpagedir/$d | grep "ftp.us.debian.org/debian" | sed 's/^[[:space:]]*//' | sed 's/^.*<a href="//' | sed 's/">.*//')
    else
        echo "Error finding link to package $d"
        do_dl=false
    fi
    if [ $do_dl == true ]; then
        wget -nc -q -P $dpkgdir/$orig_pkg $dllink
    fi
done

# put it all in an archive
tar czf $orig_pkg-$rel-$arch-with_deps.tar.gz -C $dpkgdir/$orig_pkg .

# clean up
rm -rf $tmpdir
