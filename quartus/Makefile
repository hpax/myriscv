MAKEFLAGS      += -R -r

PROJECT		= myriscv
REVISIONS	= benchmark
EXTRAREVS       =
VARIANTS        =
QU		= quartus

ALLREVS         = $(REVISIONS) $(EXTRAREVS)

# Common options for all Quartus tools
QPRI		= --lower_priority
QCPF		= $(QU)_cpf $(QPRI)
QSH		= $(QU)_sh  $(QPRI)
QSTA		= $(QU)_sta $(QPRI)
QPGM		= $(QU)_pgm $(QPRI)

# Common options for Quartus in-flow tools
QOPT		= --write_settings_files=off $(QPRI)
QMAP		= $(QU)_map $(QOPT)
QFIT		= $(QU)_fit $(QOPT)
QCDB		= $(QU)_cdb $(QOPT)
QASM		= $(QU)_asm $(QOPT)
QPOW		= $(QU)_pow $(QOPT)

outdir		= output_files

PERL		= perl
PYTHON		= python
SED		= sed
GZIP		= gzip

PREREQFILES = $(foreach rev,$(ALLREVS),$(foreach coffmt,jic pof, \
		$(outdir)/$(rev).$(coffmt).cof))

alltarg := sof pof jic rbf rbf.gz rpf rpf.gz rpd rpd.gz sta.rpt txt # pow.rpt
allout   = $(foreach o,$(alltarg),$(outdir)/$(1).$(o))

.SUFFIXES:

.SECONDARY:

.DELETE_ON_ERROR:

all: $(ALLREVS:=.targets)

-include $(ALLREVS:=.deps)

.PHONY: $(ALLREVS)
$(ALLREVS): prereq
	$(MAKE) $@.targets

.PHONY: %.targets
%.targets:
	$(MAKE) $(call allout,$*)

.PHONY: %.update
%.update:
	$(MAKE) $(call upout,$*)

.PHONY: $(VARIANTS)
$(VARIANTS):
	$(MAKE) $(outdir)/$@/variant.stamp

.PHONY: %.vtargets
%.vtargets:
	$(MAKE) --old-file=$(outdir)/$*.fit.rpt $(call varout,$*)

$(outdir)/%/variant.stamp: mif/%.mif \
			   $(foreach rev,$(ALLREVS),$(outdir)/$(rev).fit.rpt)
	-rm -rf var/$* $(outdir)/$*
	mkdir -p var/$* var/$*/mif $(outdir)/$*
	( cd $(outdir)/$* && ln -sf ../*.asm.rpt ../*.fit.rpt . )
	cp -alf Makefile *.deps *.qpf *.qsf *.pins scripts \
		db incremental_db var/$*/
	( cd var/$* && ln -sf ../../$(outdir)/$* ./output )
	$(MAKE) -C var/$* $(ALLREVS:=.vtargets)
	echo '$(BUILDDATE)' > $@

$(outdir)/%.map.rpt: %.qsf
	$(QMAP) $(PROJECT) -c $*

$(outdir)/%.fit.rpt: $(outdir)/%.map.rpt
	$(QFIT) $(PROJECT) -c $*

$(outdir)/%.sof: $(outdir)/%.fit.rpt
	$(QASM) $(PROJECT) -c $*

$(outdir)/%.sta.rpt: $(outdir)/%.fit.rpt | $(outdir)/%.sof
	$(QSTA) $(PROJECT) -c $*

$(outdir)/%.pow.rpt: $(outdir)/%.sta.rpt | $(outdir)/%.sof
	$(QPOW) $(PROJECT) -c $*

# Summary of LE count and fMAX extracted from reports
$(outdir)/%.txt: gettotal.pl $(outdir)/%.fit.rpt $(outdir)/%.sta.rpt
	$(PERL) $^ > $@

$(foreach rev,$(ALLREVS),$(outdir)/$(rev).%.cof): %.cof.xml $(outdir)
	$(SED) \
	-e 's|@@PROJECT@@|$(@F:.$*.cof=)|g' \
	-e 's|@@OUTDIR@@|$(outdir)|g' \
	$< > $@

$(outdir)/%.jic: $(outdir)/%.jic.cof $(outdir)/%.sof
	$(QCPF) -o bitstream_compression=on -c $<

$(outdir)/%.pof: $(outdir)/%.pof.cof $(outdir)/%.sof
	$(QCPF) -o bitstream_compression=on -c $<

# Raw Binary File, compact data for transient programming.
$(outdir)/%.rbf: $(outdir)/%.sof
	$(QCPF) -c $< $@

# Raw Programmer Data, for loading into flash, includes all contents
# but is rather large if not compressed. Adjust bit ordering to match
# SPI...
$(outdir)/%.rpd: $(outdir)/%.pof
	$(QCPF) -c -o bitstream_compression=on -o rpd_little_endian=off $< $@

# RPD file for the FPGA only. The necessary length can be gotten from
# generating a compressed .rbf, but that file is not valid for flashing
# even if bit-reversed due to header(?) differences.
$(outdir)/%.z.rbf: $(outdir)/%.sof
	$(QCPF) -c -o bitstream_compression=on $< $@

$(outdir)/%.rpf: $(outdir)/%.rpd $(outdir)/%.z.rbf
	dd if=$< of=$@ bs=$$(wc -c < $(@:.rpf=.z.rbf)) count=1

$(outdir)/%.gz: $(outdir)/%
	$(GZIP) -9 < $< > $@

# Prerequisite directories and files
$(outdir):
	mkdir -p $@

.PHONY: prereq
prereq: $(outdir)
	for d in $(SUBDIRS); do $(MAKE) -C $$d; done
	$(MAKE) $(PREREQFILES)

# Clean out SignalTap
signalclean:
	for f in *.qsf; do \
		$(PERL) -ne 'print unless (/(SIGNALTAP_FILE\b|\bENABLE_SIGNALTAP\b|\bSLD_FILE\b|SLD_NODE_)/);' < $$f > $$f.tmp && \
		mv -f $$f.tmp $$f ; \
	done

# Programming targets. Environment JTAG_CABLE can override the default,
# which is otherwise the first cable found.
rpar := )
JTAG_CABLE ?= $(shell jtagconfig --enum | sed -ne 's/^1$(rpar) //p')

# Transient programming
program-%: $(outdir)/%.sof
	$(QPGM) -c '$(JTAG_CABLE)' -m JTAG -o 'p;$(outdir)/$*.sof'

# Permanent programming in flash
flash-%: $(outdir)/%.jic
	$(QPGM) -c '$(JTAG_CABLE)' -m JTAG -i -o 'pvbi;$(outdir)/$*.jic'

%.deps: %.qsf scripts/qsfdeps.pl
	$(PERL) scripts/qsfdeps.pl $* $@ $<

clean:
	for d in $(SUBDIRS); do $(MAKE) -C $$d clean; done
	rm -rf db incremental_db var simulation/modelsim \
	greybox_tmp */greybox_tmp iodevs.vh
	for d in $(ALLREVS); do \
		rm -f $$d/*.rpt $$d/*.rpt $$d/*.summary $$d/*.smsg  \
		$$d/*.htm $$d/*.htm_files $$d/*.map $$d/*.eqn $$d/*.sld \
		$$d/*.done ; \
	done

spotless: clean
	for d in $(SUBDIRS); do $(MAKE) -C $$d spotless; done
	rm -rf $(outdir) *.deps *~ \#*~

deps: Makefile
