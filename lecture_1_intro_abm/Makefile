TEX = pdflatex --shell-escape
BIB = bibtex
SRC = main.tex
JOB = main

all: $(JOB).pdf

$(JOB).pdf: $(SRC) example.bib
	$(TEX) $(SRC)
	$(BIB) $(JOB)
	$(TEX) $(SRC)
	$(TEX) $(SRC)

clean:
	rm -f *.aux *.bbl *.blg *.log *.nav *.out *.snm *.toc *.vrb *.synctex.gz

distclean: clean
	rm -f $(JOB).pdf

.PHONY: all clean distclean
