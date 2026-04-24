CONFORMANCE_CORE    := conformance/core.txt
CONFORMANCE_EXT     := conformance/extended.txt
CONFORMANCE_XML     := conformance/xml.txt
CONFORMANCE_MD      := conformance/md.txt

LIB_NAME   := libcx
VCX_DYLIB  := vcx/target/$(LIB_NAME).dylib
VCX_SO     := vcx/target/$(LIB_NAME).so
DIST_DIR   := dist
PREFIX     ?= /usr/local

# ── Ruby / Go / TypeScript / Java / Kotlin / C# / Swift toolchain paths ──────
RUBY        := /opt/homebrew/opt/ruby/bin/ruby
SWIFT       := /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift
SWIFT_FLAGS := SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DOTNET      := DOTNET_ROOT=/opt/homebrew/opt/dotnet/libexec /opt/homebrew/opt/dotnet/libexec/dotnet
JAVA_HOME_ARM64 := /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home

.PHONY: all build build-vcx build-lib build-rust \
        build-ruby build-go build-typescript build-java build-kotlin build-csharp build-csharp-api build-swift \
        build-lsp build-vscode build-editors \
        publish publish-push \
        dist install uninstall install-cli uninstall-cli verify-cli promote-cli \
        test test-python test-vcx test-rust \
        test-ruby test-ruby-api test-go test-typescript test-java test-kotlin test-csharp test-csharp-api test-swift \
        test-python-api test-python-stream test-v test-vcx-api test-vcx-stream test-typescript-api test-go-api \
        conform conform-vcx conform-md bench bench-python \
        examples example-python example-v example-go example-rust example-typescript \
        example-java example-kotlin example-csharp example-ruby example-swift \
        demos demo-v demo-go demo-rust demo-typescript demo-java demo-kotlin demo-csharp demo-ruby demo-swift \
        clean

all: build

# ── Build ──────────────────────────────────────────────────────────────────────

build: build-vcx build-rust build-ruby build-go build-typescript build-java build-kotlin build-csharp build-swift

build-vcx:
	$(MAKE) -C vcx build

build-rust: build-vcx
	cargo build --manifest-path lang/rust/cxlib/Cargo.toml --release

build-ruby: build-vcx
	@echo "Ruby binding: no compile step needed"

build-go: build-vcx
	cd lang/go/cxlib && go build ./...

build-typescript: build-vcx
	cd lang/typescript/cxlib && npm install --silent && npm run build

build-java: build-vcx
	mvn -f lang/java/cxlib/pom.xml -q package -DskipTests

build-kotlin: build-vcx
	cd lang/kotlin/cxlib && JAVA_HOME=$(JAVA_HOME_ARM64) gradle assemble -q

build-csharp: build-vcx
	$(DOTNET) build lang/csharp/cxlib/cxlib.csproj -c Release --nologo -v:m

build-csharp-api: build-csharp
	$(DOTNET) build lang/csharp/api_test/api_test.csproj -c Release --nologo -v:m

build-swift: build-vcx
	$(SWIFT_FLAGS) $(SWIFT) build --package-path lang/swift/cxlib -c release

build-lib: build-vcx

# Copy vcx dylib + header into dist/ (V implementation is primary)
dist: build-vcx
	mkdir -p $(DIST_DIR)/lib $(DIST_DIR)/include
	cp -f include/cx.h $(DIST_DIR)/include/
	@if [ -f $(VCX_DYLIB) ]; then cp -f $(VCX_DYLIB) $(DIST_DIR)/lib/libcx.dylib; fi
	@if [ -f $(VCX_SO)    ]; then cp -f $(VCX_SO)    $(DIST_DIR)/lib/libcx.so; fi
	@echo "dist: $(DIST_DIR)/include/cx.h  $(DIST_DIR)/lib/"

# Install libcx system-wide (default: /usr/local; override with PREFIX=...)
install: dist
	install -d $(PREFIX)/lib $(PREFIX)/include $(PREFIX)/lib/pkgconfig
	@if [ -f $(DIST_DIR)/lib/libcx.dylib ]; then install -m 755 $(DIST_DIR)/lib/libcx.dylib $(PREFIX)/lib/; fi
	@if [ -f $(DIST_DIR)/lib/libcx.so    ]; then install -m 755 $(DIST_DIR)/lib/libcx.so    $(PREFIX)/lib/; fi
	install -m 644 $(DIST_DIR)/include/cx.h $(PREFIX)/include/
	sed "s|@PREFIX@|$(PREFIX)|g" cx.pc.in > $(PREFIX)/lib/pkgconfig/cx.pc
	@echo "installed libcx → $(PREFIX)/lib/  header → $(PREFIX)/include/  pkg-config → $(PREFIX)/lib/pkgconfig/cx.pc"

uninstall:
	rm -f $(PREFIX)/lib/libcx.dylib $(PREFIX)/lib/libcx.so
	rm -f $(PREFIX)/include/cx.h
	rm -f $(PREFIX)/lib/pkgconfig/cx.pc
	@echo "uninstalled libcx from $(PREFIX)"

# Install the verified CLI separately from the libcx shared library.
install-cli: build-vcx
	install -d $(PREFIX)/bin
	install -m 755 vcx/target/cx $(PREFIX)/bin/cx
	@echo "installed cx CLI → $(PREFIX)/bin/cx"

uninstall-cli:
	rm -f $(PREFIX)/bin/cx
	@echo "uninstalled cx CLI from $(PREFIX)/bin/cx"

# Smoke-test the staged CLI before promotion.
verify-cli: build-vcx
	./vcx/target/cx --help >/dev/null
	./vcx/target/cx --json examples/config.cx >/dev/null
	@echo "verified staged CLI at vcx/target/cx"

promote-cli: verify-cli install-cli
	@echo "promoted verified cx CLI to $(PREFIX)/bin/cx"

# ── Test ───────────────────────────────────────────────────────────────────────

test: test-python test-vcx test-v test-rust test-ruby test-go test-typescript test-java test-kotlin test-csharp test-swift

test-python: build-vcx
	python lang/python/conformance.py
	python lang/python/test_api.py
	python lang/python/test_stream.py
	python lang/python/test_cxpath.py
	python lang/python/test_transform.py
	python lang/python/test_immutability.py

test-python-api: build-vcx
	python lang/python/test_api.py

test-python-stream: build-vcx
	python lang/python/test_stream.py

test-rust: build-rust
	cargo test --manifest-path lang/rust/cxlib/Cargo.toml -- --test-threads=1

test-vcx: build-vcx
	$(MAKE) -C vcx conform-all

test-v: build-vcx
	v run lang/v/conformance.v
	v test lang/v/tests/api_test.v
	v test lang/v/tests/stream_test.v

test-vcx-api: build-vcx
	v test lang/v/tests/api_test.v

test-vcx-stream: build-vcx
	v test vcx/tests/stream_test.v

test-ruby: build-vcx
	$(RUBY) lang/ruby/conformance.rb
	$(RUBY) lang/ruby/test_api.rb

test-ruby-api: build-vcx
	$(RUBY) lang/ruby/test_api.rb

test-go: build-go
	cd lang/go/cxlib && go test ./...
	cd lang/go/conformance && go run .

test-go-api: build-go
	cd lang/go/cxlib && go test ./...

test-typescript: build-typescript
	cd lang/typescript/cxlib && npm run conform
	npx tsx lang/typescript/api_test.ts

test-typescript-api: build-typescript
	npx tsx lang/typescript/api_test.ts

test-java: build-java
	mvn -f lang/java/cxlib/pom.xml -q test

test-kotlin: build-kotlin
	cd lang/kotlin/cxlib && JAVA_HOME=$(JAVA_HOME_ARM64) gradle test -q

test-csharp: build-csharp build-csharp-api
	$(DOTNET) run --project lang/csharp/conformance/conformance.csproj -c Release
	$(DOTNET) run --project lang/csharp/api_test/api_test.csproj -c Release

test-csharp-api: build-csharp-api
	$(DOTNET) run --project lang/csharp/api_test/api_test.csproj -c Release

test-swift: build-swift
	$(SWIFT_FLAGS) $(SWIFT) test --package-path lang/swift/cxlib

conform-md: build-vcx
	$(MAKE) -C vcx conform-md

# ── Conformance ────────────────────────────────────────────────────────────────

conform: conform-vcx

conform-vcx: build-vcx
	$(MAKE) -C vcx conform-all

# ── Examples (transform showcase) ────────────────────────────────────────────

examples: example-python example-v example-go example-rust example-typescript \
          example-java example-kotlin example-csharp example-ruby example-swift

example-python: build-vcx
	python lang/python/examples/transform.py

example-v: build-vcx
	v run lang/v/examples/transform.v

example-go: build-go
	cd lang/go/cxlib && go run ./examples/transform/

example-rust: build-rust
	cargo run --example transform --manifest-path lang/rust/cxlib/Cargo.toml

example-typescript: build-typescript
	npx tsx lang/typescript/cxlib/examples/transform.ts

example-java: build-java
	mvn -f lang/java/cxlib/pom.xml -q exec:java -Dexec.mainClass=cx.examples.Transform

example-kotlin: build-kotlin
	cd lang/kotlin/cxlib && JAVA_HOME=$(JAVA_HOME_ARM64) gradle run -q

example-csharp: build-csharp
	$(DOTNET) run --project lang/csharp/examples/transform/transform.csproj

example-ruby: build-vcx
	$(RUBY) lang/ruby/cxlib/examples/transform.rb

example-swift: build-swift
	$(SWIFT_FLAGS) $(SWIFT) run --package-path lang/swift/cxlib transform

# ── Demos (Document Model + Streaming + CXPath + Transform) ──────────────────

demos: demo-v demo-go demo-rust demo-typescript demo-java demo-kotlin demo-csharp demo-ruby demo-swift

demo-v: build-vcx
	v run lang/v/examples/demo.v

demo-go: build-go
	cd lang/go/cxlib && go run ./examples/demo/

demo-rust: build-rust
	cargo run --example demo --manifest-path lang/rust/cxlib/Cargo.toml

demo-typescript: build-typescript
	npx tsx lang/typescript/cxlib/examples/demo.ts

demo-java: build-java
	mvn -f lang/java/cxlib/pom.xml -q exec:java -Dexec.mainClass=cx.Demo

demo-kotlin: build-kotlin
	cd lang/kotlin/cxlib && JAVA_HOME=$(JAVA_HOME_ARM64) gradle demo -q

demo-csharp: build-csharp
	$(DOTNET) run --project lang/csharp/examples/readme_demo/readme_demo.csproj -c Release

demo-ruby: build-vcx
	$(RUBY) lang/ruby/cxlib/examples/demo.rb

demo-swift: build-swift
	$(SWIFT_FLAGS) $(SWIFT) run --package-path lang/swift/cxlib Demo

# ── Publish to public repo ────────────────────────────────────────────────────

publish:
	@bash scripts/publish.sh

publish-push:
	@bash scripts/publish_push.sh

# ── Editor tooling ────────────────────────────────────────────────────────────

build-lsp:
	cd tooling/lsp && npm install --silent && npm run build

build-vscode: build-lsp
	cd tooling/vscode && npm install --silent && npm run build && npx vsce package --no-dependencies --allow-missing-repository

build-editors: build-lsp build-vscode

# ── Benchmark ──────────────────────────────────────────────────────────────────

bench: build-vcx
	python bench_report.py

bench-python: build-vcx
	python lang/python/bench.py

# ── Clean ──────────────────────────────────────────────────────────────────────

clean:
	$(MAKE) -C vcx clean
	rm -rf $(DIST_DIR)
	cargo clean --manifest-path lang/rust/cxlib/Cargo.toml
	find lang/csharp -type d \( -name bin -o -name obj \) -exec rm -rf {} + 2>/dev/null || true
	rm -rf lang/kotlin/cxlib/.gradle
	find lang/python -name '*.pyc' -delete
	find lang/python -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
