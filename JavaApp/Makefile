# Prerequisite variables
SOURCEDIR := src
OUTPUTDIR := build

SOURCES := $(shell find $(SOURCEDIR) -type f -name '*.java')
CLASSES := $(SOURCES:$(SOURCEDIR)/%.java=$(OUTPUTDIR)/%.class)

TARGETS := $(shell find $(SOURCEDIR) -mindepth 1 -maxdepth 1 -type d)
TARGETS := $(TARGETS:$(SOURCEDIR)/%=$(OUTPUTDIR)/%.jar)

# Add all jars to classpath and allow compiling with private API
JCFLAGS := -cp "$(subst $() $(),:,$(wildcard $(SOURCEDIR)/*/):$(wildcard libs/*/*.jar))" -XDignore.symbol.file

all: $(TARGETS)
	
# Sometimes the CI produces empty class files (javac race on the runner). Rather
# than failing the whole build, recompile each affected source once and retry.
check_empty_classes:
	@set -e; \
	echo "Checking for empty class files"; \
	for f in $$(find $(OUTPUTDIR) -name '*.class' -size 0 -not -path '$(OUTPUTDIR)/classes/*'); do \
		rel=$${f#$(OUTPUTDIR)/}; \
		src=$(SOURCEDIR)/$${rel%.class}.java; \
		if [ ! -f "$$src" ]; then echo "Empty class without source: $$f"; exit 1; fi; \
		echo "Recompiling empty class $$f from $$src"; \
		$(BOOTJDK)/javac $(JCFLAGS) -d $(OUTPUTDIR)/classes "$$src"; \
		inner=$$(echo "$$rel" | cut -d/ -f2-); \
		mkdir -p "$$(dirname "$$f")"; \
		cp "$(OUTPUTDIR)/classes/$$inner" "$$f"; \
	done; \
	if [ -n "$$(find $(OUTPUTDIR) -name '*.class' -size 0 -not -path '$(OUTPUTDIR)/classes/*')" ]; then \
		echo "Error: empty class files remain after retry"; \
		exit 1; \
	fi

# Rules for building java class
$(CLASSES): $(OUTPUTDIR)/%.class: $(SOURCEDIR)/%.java
	@set -e
	$(eval TARGET=$(word 2, $(subst /, ,$@)))
	@mkdir -p $(OUTPUTDIR)/classes
	@mkdir -p $(dir $@)
	@echo "Compiling $<"
	@$(BOOTJDK)/javac $(JCFLAGS) -d $(OUTPUTDIR)/classes $<
	@cp $(@:$(OUTPUTDIR)/$(TARGET)/%.class=$(OUTPUTDIR)/classes/%*.class) $(dir $@)/

# Ensure all classes are compiled before checking them.
check_empty_classes: $(CLASSES)

$(OUTPUTDIR)/launcher.jar: $(CLASSES) check_empty_classes
	@set -e
	@echo "Creating $@"
	@$(BOOTJDK)/jar -cf $@ -C $(basename $@) .

$(OUTPUTDIR)/lwjgl.jar: $(CLASSES) check_empty_classes
	@set -e
	@echo "Creating $@"
	@mkdir -p $(OUTPUTDIR)/lwjgl_lib
	@cd $(OUTPUTDIR)/lwjgl_lib && find ../../libs/lwjgl -name 'lwjgl*.jar' -exec $(BOOTJDK)/jar -xf {} \; && rm -rf META-INF
	@cp -R $(OUTPUTDIR)/lwjgl/* $(OUTPUTDIR)/lwjgl_lib/
	@$(BOOTJDK)/jar -cf $@ -C $(OUTPUTDIR)/lwjgl_lib .

$(OUTPUTDIR)/patchjna_agent.jar: $(CLASSES)
	@set -e
	@mv $(basename $@)/com/sun/jna/Platform.class $(basename $@)/com/sun/jna/Platform.class.patch
	@echo "Creating $@"
	@$(BOOTJDK)/jar -cfm $@ $(SOURCEDIR)/patchjna_agent.txt -C $(basename $@) .

clean:
	rm -rf $(OUTPUTDIR)

.SUFFIXES: .java
.PHONY: all clean
