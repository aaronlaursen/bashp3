#!/bin/bash

#PATHS
TMPLOC=/tmp/mp3/bash
INFIFO=$TMPLOC/in
OUTFIFO=$TMPLOC/out
CONFIFO=$TMPLOC/control
PLAYLIST=$TMPLOC/playlist

#setup pipes
rm -f $INFIFO
rm -f $OUTFIFO
mkdir -p $TMPLOC
mkfifo $INFIFO
mkfifo $OUTFIFO

#setup playlist
touch $PLAYLIST

#helper variables
PLAYING="0"
INDEX="1"
PLAYID=""
LOOP="0"



#useful functions
function playdecoded {
    aplay -q && echo "END" > $INFIFO 
}

function playindex {
    songpath=`getatindex`
    case `echo "$songpath" | rev | cut -d '.' -f 1 | rev` in
        mp3)
            lame --decode --quiet "$songpath" - | playdecoded
            ;;
        *)
            ffmpeg -v quiet -i "$songpath" - | playdecoded
            ;;
    esac
}

function shuffle {
    shuf $PLAYLIST >$PLAYLIST.tmp
    mv $PLAYLIST.tmp $PLAYLIST
}

function play {
    if [ ! -z $PLAYID ]; then 
        toggle
    else 
        stopplay
        playindex &
        sleep 0.2
        PLAYID=`pidof -s aplay`
        PLAYING="1"
    fi
}

function stopplay {
    if [ ! -z $PLAYID ]; then
        kill "$PLAYID"
    fi
    PLAYING="0"
    PLAYID=""
}

function next {
    INDEX=$[$INDEX+1]
    stopplay
    if [ $INDEX -gt `getmaxindex` ]; then
        INDEX="1" 
        if [ $LOOP = "1" ]; then
            play
        fi
    else 
        play
    fi
}

function getmaxindex {
    sed -n '$=' $PLAYLIST
}

function prev {
    INDEX=$[$INDEX-1]
    stopplay
    if [ $INDEX = "0" ]; then
        INDEX=`sed -n '$=' $PLAYLIST`
    fi
    play
}

function add {
    echo "$@" >> $PLAYLIST
}

function addat {
    sed -i -e "$1 i `echo "$@" |cut -d ' ' -f 2-` " $PLAYLIST
}

function remove {
    sed -i "$1 d" $PLAYLIST
}
    

function adddir {
    OLDPWD=`pwd`
    cd "`echo "$@"|sed 's/\ /\\ /g'`"
    for i in *; do
        add "$@/$i"
    done
    cd $OLDPWD
}

function getatindex {
    head -$INDEX $PLAYLIST | tail -1
}

function clearlist {
    stopplay
    cat /dev/null > $PLAYLIST
}

function toggle {
    if [ ! -z $PLAYID ]; then 
        if [ $PLAYING = "0" ];then
            kill -18 $PLAYID
            PLAYING="1"
        else 
            kill -19 $PLAYID
            PLAYING="0"
        fi
    fi
}

function getid3 {
    TITLE="`id3info "$1" | grep '^=== TIT2' | sed -e 's/.*: //g'`"
    ARTIST="`id3info "$1" | grep '^=== TPE1' | sed -e 's/.*: //g'`"
    ALBUM="`id3info "$1" | grep '^=== TALB' | sed -e 's/.*: //g'`"
    YEAR="`id3info "$1" | grep '^=== TYER' | sed -e 's/.*: //g'`"
    TRACKNUM="`id3info "$1" | grep '=== TRCK' | sed -e 's/.*: //g'`"

    SHORT=`echo $ARTIST | cut -d ';' -f -2`
    if [ "$SHORT" != "$ARTIST" ]; then
        ARTIST="$SHORT ..."
    fi

    echo "| $ARTIST | $TITLE | $ALBUM | $YEAR | $TRACKNUM"
}

function formatoutput {
    data=`getid3 "$@"`
    echo $data |cut -d '|' -f -4
}

function list {
    i=1
    out="  # | Artist | Title | Album \n"
    out="$out----|--------------------|------------------|------------------ "
    while read l; do
        out="$out\n"
        if [ $i = $INDEX ]; then
            out="$out> "
        else
            out="$out  "
        fi
        out="$out$i `formatoutput "$l"`"
        i=$[$i+1]
    done < $PLAYLIST
    echo -e "$out"
}
            
function jump {
    if [ "$1" -gt "0" ];then
        if [ "$1" -le `getmaxindex` ]; then
            INDEX="$1"
            stopplay
            play
        fi
    fi
}

function showcurrent {
    current="`getatindex`"
    echo -e "# | Artist | Title | Album | Year | Track\n$INDEX `getid3 \"$current\"`"
}

#main
while true; do
    LINE=`cat $INFIFO`
    case `echo $LINE | cut -d ' ' -f 1` in
        END)
            PLAYID=""
            next
            ;;
        play)
            play
            ;;
        next)
            next
            ;;
        prev)
            prev
            ;;
        adddir)
            adddir `echo $LINE | cut -d ' ' -f 2-`
            ;;
        add)
            add `echo $LINE | cut -d ' ' -f 2-`
            ;;
        addat)
            addat `echo $LINE | cut -d ' ' -f 2-`
            ;;
        stop)
            stopplay
            ;;
        toggle)
            toggle
            ;;
        pause)
            if [ $PLAYING = "1" ]; then
                kill -19 $PLAYID
                PLAYING="0"
            fi
            ;;
        list)
            list |column -t -s "|" > $OUTFIFO
            continue
            ;;
        current)
            showcurrent |column -t -s "|" >$OUTFIFO
            continue
            ;;
        clear)
            clearlist
            ;;
        jump)
            jump `echo $LINE | cut -d ' ' -f 2-`
            ;;
        loop)
            LOOP="$2"
            ;;
        shuffle)
            shuffle
            ;;
        remove)
            remove `echo $LINE |cut -d ' ' -f 2-`
            ;;
        *)
            echo `echo $LINE | cut -d ' ' -f 1` > $OUTFIFO
            ;;
    esac
    cat /dev/null > $OUTFIFO
done

