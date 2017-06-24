#!/bin/csh
echo
echo Kernel Modules...
echo
foreach f (ExSite/*.pm)
    set mod = `basename $f .pm`
    pod2html --infile=$f --outfile=../doc/${mod}.html --title=${mod}.pm
    echo $mod
end
echo
echo Plug-in Modules...
echo
foreach f (Modules/*.pm)
    set mod = `basename $f .pm`
    pod2html --infile=$f --outfile=../doc/${mod}.html --title=${mod}.pm
    echo $mod
end
