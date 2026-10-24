import 'dart:io';

bool get isWindows => Platform.isWindows;

bool get isLinux => Platform.isLinux;

bool get isMacOS => Platform.isMacOS;

bool get isAndroid => Platform.isAndroid;

bool get isIOS => Platform.isIOS;

String? environment(String name) => Platform.environment[name];
