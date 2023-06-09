// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#define FML_USED_ON_EMBEDDER

#include "flutter/shell/platform/darwin/ios/framework/Source/FlutterDartProject_Internal.h"

#include "flutter/common/task_runners.h"
#include "flutter/fml/message_loop.h"
#include "flutter/fml/platform/darwin/scoped_nsobject.h"
#include "flutter/shell/common/shell.h"
#include "flutter/shell/common/switches.h"
#include "flutter/shell/platform/darwin/common/command_line.h"
#include "flutter/shell/platform/darwin/ios/framework/Headers/FlutterViewController.h"

extern "C" {
#if FLUTTER_RUNTIME_MODE == FLUTTER_RUNTIME_MODE_DEBUG
// Used for debugging dart:* sources.
extern const uint8_t kPlatformStrongDill[];
extern const intptr_t kPlatformStrongDillSize;
#endif
}

static const char* kApplicationKernelSnapshotFileName = "kernel_blob.bin";

static flutter::Settings DefaultSettingsForProcess(NSBundle* bundle = nil) {
  auto command_line = flutter::CommandLineFromNSProcessInfo();

  // Precedence:
  // 1. Settings from the specified NSBundle.
  // 2. Settings passed explicitly via command-line arguments.
  // 3. Settings from the NSBundle with the default bundle ID.
  // 4. Settings from the main NSBundle and default values.

  NSBundle* mainBundle = [NSBundle mainBundle];
  NSBundle* engineBundle = [NSBundle bundleForClass:[FlutterViewController class]];

  bool hasExplicitBundle = bundle != nil;
  if (bundle == nil) {
    bundle = [NSBundle bundleWithIdentifier:[FlutterDartProject defaultBundleIdentifier]];
  }
  if (bundle == nil) {
    bundle = mainBundle;
  }

  auto settings = flutter::SettingsFromCommandLine(command_line);

  settings.task_observer_add = [](intptr_t key, fml::closure callback) {
    fml::MessageLoop::GetCurrent().AddTaskObserver(key, std::move(callback));
  };

  settings.task_observer_remove = [](intptr_t key) {
    fml::MessageLoop::GetCurrent().RemoveTaskObserver(key);
  };

  // The command line arguments may not always be complete. If they aren't, attempt to fill in
  // defaults.

  // Flutter ships the ICU data file in the the bundle of the engine. Look for it there.
  if (settings.icu_data_path.size() == 0) {
    NSString* icuDataPath = [engineBundle pathForResource:@"icudtl" ofType:@"dat"];
    if (icuDataPath.length > 0) {
      settings.icu_data_path = icuDataPath.UTF8String;
    }
  }

  // Checks to see if the flutter assets directory is already present.
  if (settings.assets_path.size() == 0) {
    NSString* assetsName = [FlutterDartProject flutterAssetsName:bundle];
    NSString* assetsPath = [bundle pathForResource:assetsName ofType:@""];

    if (assetsPath.length == 0) {
      assetsPath = [mainBundle pathForResource:assetsName ofType:@""];
    }

    if (assetsPath.length == 0) {
      NSLog(@"Failed to find assets path for \"%@\"", assetsName);
    } else {
      settings.assets_path = assetsPath.UTF8String;
    }
  }

#if FLUTTER_RUNTIME_MODE == FLUTTER_RUNTIME_MODE_DEBUG
  // There are no ownership concerns here as all mappings are owned by the
  // embedder and not the engine.
  auto make_mapping_callback = [](const uint8_t* mapping, size_t size) {
    return [mapping, size]() { return std::make_unique<fml::NonOwnedMapping>(mapping, size); };
  };

  settings.dart_library_sources_kernel =
      make_mapping_callback(kPlatformStrongDill, kPlatformStrongDillSize);
#endif  // FLUTTER_RUNTIME_MODE == FLUTTER_RUNTIME_MODE_DEBUG

  return settings;
}

@implementation FlutterDartProject {
  fml::scoped_nsobject<NSBundle> _precompiledDartBundle;
  flutter::Settings _settings;
}

#pragma mark - Override base class designated initializers

- (instancetype)init {
  return [self initWithPrecompiledDartBundle:nil];
}

#pragma mark - Designated initializers

- (instancetype)initWithPrecompiledDartBundle:(NSBundle*)bundle {
  self = [super init];

  if (self) {
    _precompiledDartBundle.reset([bundle retain]);
    _settings = DefaultSettingsForProcess(bundle);
  }

  return self;
}

#pragma mark - Settings accessors

- (const flutter::Settings&)settings {
  return _settings;
}

- (flutter::RunConfiguration)runConfiguration {
  return [self runConfigurationForEntrypoint:nil];
}

- (flutter::RunConfiguration)runConfigurationForEntrypoint:(NSString*)entrypointOrNil {
  return [self runConfigurationForEntrypoint:entrypointOrNil libraryOrNil:nil];
}

- (flutter::RunConfiguration)runConfigurationForEntrypoint:(NSString*)entrypointOrNil
                                              libraryOrNil:(NSString*)dartLibraryOrNil {
  flutter::RunConfiguration config;
  return config;
}

#pragma mark - Assets-related utilities

+ (NSString*)flutterAssetsName:(NSBundle*)bundle {
  if (bundle == nil) {
    bundle = [NSBundle bundleWithIdentifier:[FlutterDartProject defaultBundleIdentifier]];
  }
  if (bundle == nil) {
    bundle = [NSBundle mainBundle];
  }
  NSString* flutterAssetsName = [bundle objectForInfoDictionaryKey:@"FLTAssetsPath"];
  if (flutterAssetsName == nil) {
    flutterAssetsName = @"Frameworks/App.framework/flutter_assets";
  }
  return flutterAssetsName;
}

+ (NSString*)lookupKeyForAsset:(NSString*)asset {
  return [self lookupKeyForAsset:asset fromBundle:nil];
}

+ (NSString*)lookupKeyForAsset:(NSString*)asset fromBundle:(NSBundle*)bundle {
  NSString* flutterAssetsName = [FlutterDartProject flutterAssetsName:bundle];
  return [NSString stringWithFormat:@"%@/%@", flutterAssetsName, asset];
}

+ (NSString*)lookupKeyForAsset:(NSString*)asset fromPackage:(NSString*)package {
  return [self lookupKeyForAsset:asset fromPackage:package fromBundle:nil];
}

+ (NSString*)lookupKeyForAsset:(NSString*)asset
                   fromPackage:(NSString*)package
                    fromBundle:(NSBundle*)bundle {
  return [self lookupKeyForAsset:[NSString stringWithFormat:@"packages/%@/%@", package, asset]
                      fromBundle:bundle];
}

+ (NSString*)defaultBundleIdentifier {
  return @"io.flutter.flutter.app";
}

@end
