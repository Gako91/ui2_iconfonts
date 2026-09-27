V ?= v

.PHONY: test ide check-ide examples examples-custom screenshot check-macos check-ios check-android check-linux check-windows check-custom-macos check-custom-windows check-custom check-backends icons

test:
	$(V) test .

# Rewrites the bundled Material Icons name table from the list the Material
# Icons package ships, so a name that appears there is a name ui2 answers to.
# The list lives outside this repository; see docs/icon-fonts.md.
ICOND_LIST ?= MaterialIcons-Regular.codepoints

icons:
	$(V) run tools/icond.v -alias material -ttf assets/fonts/MaterialIcons-Regular.ttf \
		-codepoints $(ICOND_LIST) -out ui/icons_material.v

ide:
	$(V) run ide

check-ide:
	$(V) -check ide

examples:
	$(V) run examples/build_examples.vsh

examples-custom:
	$(V) run examples/build_examples.vsh -d ui2_custom_rendering

# Writes one frame of a custom-rendered example to a PNG, e.g.
#   make screenshot EXAMPLE=message
screenshot:
	$(V) run examples/screenshot_example.vsh $(EXAMPLE)

check-macos:
	$(V) -shared -os macos -check .

check-ios:
	$(V) -enable-globals -shared -os ios -check .

check-android:
	$(V) -shared -os android -check .

check-linux:
	$(V) -shared -os linux -check .
	$(V) -os linux -check ui/ui_linux_test.v

check-windows:
	$(V) -enable-globals -shared -os windows -check .
	$(V) -enable-globals -os windows -check windows/ui_windows_test.v

check-custom-macos:
	$(V) -d ui2_custom_rendering -shared -os macos -check .
	$(V) -d ui2_custom_rendering -os macos -check ui/ui_custom_test.v

check-custom-windows:
	$(V) -d ui2_custom_rendering -shared -os windows -check .
	$(V) -d ui2_custom_rendering -os windows -check ui/ui_custom_test.v

check-custom: check-custom-macos check-custom-windows

check-backends: check-macos check-ios check-android check-linux check-windows check-custom
