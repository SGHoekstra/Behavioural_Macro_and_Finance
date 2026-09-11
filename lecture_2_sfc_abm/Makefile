TEX = pdflatex --shell-escape -interaction=nonstopmode
BIB = bibtex

LECTURE_SRC = lecture.tex
LECTURE_JOB = lecture

TINBERGEN_SRC = Tinbergen_lecture.tex
TINBERGEN_JOB = Tinbergen_lecture

all: $(LECTURE_JOB).pdf $(TINBERGEN_JOB).pdf

$(LECTURE_JOB).pdf: $(LECTURE_SRC) example.bib
	$(TEX) $(LECTURE_SRC)
	-$(BIB) $(LECTURE_JOB)
	$(TEX) $(LECTURE_SRC)
	$(TEX) $(LECTURE_SRC)

$(TINBERGEN_JOB).pdf: $(TINBERGEN_SRC) example.bib
	$(TEX) $(TINBERGEN_SRC)
	-$(BIB) $(TINBERGEN_JOB)
	$(TEX) $(TINBERGEN_SRC)
	$(TEX) $(TINBERGEN_SRC)

# Force rebuild even if make thinks targets are up to date.
force: distclean all

clean:
	rm -f *.aux *.bbl *.blg *.log *.nav *.out *.snm *.toc *.vrb *.synctex.gz \
	      *.fdb_latexmk *.fls

distclean: clean
	rm -f $(LECTURE_JOB).pdf $(TINBERGEN_JOB).pdf

.PHONY: all clean distclean force
