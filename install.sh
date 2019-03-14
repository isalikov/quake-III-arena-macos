#!/bin/bash

set -e # exit on error

cd $HOME
git clone https://github.com/ioquake/ioq3
cd ioq3

./make-macosx.sh x86_64

cd build
cp -R release-darwin-x86_64/ /Applications/ioquake3

cd /Applications/ioquake3/baseq3

COUNT=0
while [ $COUNT -lt 9 ]; do
    curl https://q3.dayler.io/pak$COUNT.pk3 > pak$COUNT.pk3
    let COUNT+=1
done

echo "Quake 3: Arena installation successful!"

rm -rf $HOME/ioq3

read -p "Do you want to start the game now? (y/n) " -n 1 -r

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 0
else
    open /Applications/ioquake3/ioquake3.app
fi
