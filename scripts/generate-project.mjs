import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const root = path.resolve(import.meta.dirname, '..');
const id = key => crypto.createHash('sha256').update(key).digest('hex').slice(0, 24).toUpperCase();
const q = value => JSON.stringify(value);
const walk = dir => fs.readdirSync(path.join(root, dir), { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(`${dir}/${e.name}`) : [`${dir}/${e.name}`]);
const appFiles = walk('SnowOps').filter(f => f.endsWith('.swift')).sort();
const testFiles = walk('SnowOpsTests').filter(f => f.endsWith('.swift')).sort();
const objects = [];
const add = (key, body) => { objects.push(`${id(key)} = { ${body} };`); return id(key); };
for (const file of [...appFiles, ...testFiles]) {
  add(`file:${file}`, `isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${q(file)}; sourceTree = SOURCE_ROOT;`);
  add(`build:${file}`, `isa = PBXBuildFile; fileRef = ${id(`file:${file}`)};`);
}
add('appProduct', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = SnowOps.app; sourceTree = BUILT_PRODUCTS_DIR;');
add('testProduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = SnowOpsTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;');
add('sourcesGroup', `isa = PBXGroup; name = SnowOps; children = (${appFiles.map(f => id(`file:${f}`)).join(',')}); sourceTree = "<group>";`);
add('testsGroup', `isa = PBXGroup; name = SnowOpsTests; children = (${testFiles.map(f => id(`file:${f}`)).join(',')}); sourceTree = "<group>";`);
add('products', `isa = PBXGroup; name = Products; children = (${id('appProduct')}, ${id('testProduct')}); sourceTree = "<group>";`);
add('mainGroup', `isa = PBXGroup; children = (${id('sourcesGroup')}, ${id('testsGroup')}, ${id('products')}); sourceTree = "<group>";`);
add('localPackage', 'isa = XCLocalSwiftPackageReference; relativePath = .;');
add('coreProduct', `isa = XCSwiftPackageProductDependency; package = ${id('localPackage')}; productName = SnowOpsCore;`);
add('coreBuild', `isa = PBXBuildFile; productRef = ${id('coreProduct')};`);
add('testCoreProduct', `isa = XCSwiftPackageProductDependency; package = ${id('localPackage')}; productName = SnowOpsCore;`);
add('testCoreBuild', `isa = PBXBuildFile; productRef = ${id('testCoreProduct')};`);
for (const [prefix, files] of [['app', appFiles], ['test', testFiles]]) {
  add(`${prefix}Sources`, `isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${files.map(f => id(`build:${f}`)).join(',')}); runOnlyForDeploymentPostprocessing = 0;`);
  add(`${prefix}Frameworks`, `isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (${id(prefix === 'app' ? 'coreBuild' : 'testCoreBuild')}); runOnlyForDeploymentPostprocessing = 0;`);
  add(`${prefix}Resources`, 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;');
}
add('proxy', `isa = PBXContainerItemProxy; containerPortal = ${id('project')}; proxyType = 1; remoteGlobalIDString = ${id('appTarget')}; remoteInfo = SnowOps;`);
add('dependency', `isa = PBXTargetDependency; target = ${id('appTarget')}; targetProxy = ${id('proxy')};`);
const projectSettings = 'CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 26.0; SWIFT_VERSION = 6.0; SWIFT_STRICT_CONCURRENCY = complete;';
for (const mode of ['Debug', 'Release']) {
  add(`project${mode}`, `isa = XCBuildConfiguration; name = ${mode}; buildSettings = { ${projectSettings} ${mode === 'Debug' ? 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' : 'SWIFT_COMPILATION_MODE = wholemodule; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'} };`);
  const appSettings = 'PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = com.snowops.app; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = "Snow Ops"; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; TARGETED_DEVICE_FAMILY = "1,2"; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1.0; INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "Attach service photos to document completed work."; INFOPLIST_KEY_NSCameraUsageDescription = "Photograph completed services and site issues."; INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "Record location with service documentation.";';
  add(`app${mode}`, `isa = XCBuildConfiguration; name = ${mode}; buildSettings = { ${appSettings} };`);
  add(`test${mode}`, `isa = XCBuildConfiguration; name = ${mode}; buildSettings = { PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = com.snowops.tests; GENERATE_INFOPLIST_FILE = YES; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/SnowOps.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SnowOps"; BUNDLE_LOADER = "$(TEST_HOST)"; CODE_SIGN_STYLE = Automatic; };`);
}
for (const prefix of ['project', 'app', 'test']) add(`${prefix}Config`, `isa = XCConfigurationList; buildConfigurations = (${id(`${prefix}Debug`)}, ${id(`${prefix}Release`)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;`);
add('appTarget', `isa = PBXNativeTarget; buildConfigurationList = ${id('appConfig')}; buildPhases = (${id('appSources')}, ${id('appFrameworks')}, ${id('appResources')}); buildRules = (); dependencies = (); name = SnowOps; productName = SnowOps; productReference = ${id('appProduct')}; productType = "com.apple.product-type.application"; packageProductDependencies = (${id('coreProduct')});`);
add('testTarget', `isa = PBXNativeTarget; buildConfigurationList = ${id('testConfig')}; buildPhases = (${id('testSources')}, ${id('testFrameworks')}, ${id('testResources')}); buildRules = (); dependencies = (${id('dependency')}); name = SnowOpsTests; productName = SnowOpsTests; productReference = ${id('testProduct')}; productType = "com.apple.product-type.bundle.unit-test"; packageProductDependencies = (${id('testCoreProduct')});`);
add('project', `isa = PBXProject; attributes = { LastUpgradeCheck = 2600; TargetAttributes = { ${id('appTarget')} = { CreatedOnToolsVersion = 26.0; }; ${id('testTarget')} = { CreatedOnToolsVersion = 26.0; TestTargetID = ${id('appTarget')}; }; }; }; buildConfigurationList = ${id('projectConfig')}; compatibilityVersion = "Xcode 16.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = ${id('mainGroup')}; productRefGroup = ${id('products')}; projectDirPath = ""; projectRoot = ""; targets = (${id('appTarget')}, ${id('testTarget')}); packageReferences = (${id('localPackage')});`);
const projectDir = path.join(root, 'SnowOps.xcodeproj');
fs.mkdirSync(path.join(projectDir, 'xcshareddata/xcschemes'), { recursive: true });
fs.writeFileSync(path.join(projectDir, 'project.pbxproj'), `// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n${objects.join('\n')}\n}; rootObject = ${id('project')}; }\n`);
const reference = (target, name, product) => `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id(target)}" BuildableName="${product}" BlueprintName="${name}" ReferencedContainer="container:SnowOps.xcodeproj"/>`;
fs.writeFileSync(path.join(projectDir, 'xcshareddata/xcschemes/SnowOps.xcscheme'), `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">${reference('appTarget', 'SnowOps', 'SnowOps.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">${reference('testTarget', 'SnowOpsTests', 'SnowOpsTests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">${reference('appTarget', 'SnowOps', 'SnowOps.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES"><BuildableProductRunnable runnableDebuggingMode="0">${reference('appTarget', 'SnowOps', 'SnowOps.app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>`);
console.log(`Generated SnowOps.xcodeproj: ${appFiles.length} application files, ${testFiles.length} test files; no third-party dependencies.`);
