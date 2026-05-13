import 'package:flutter/material.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

/// Default navigation buttons: Back, Home, App Switch.
const defaultNavButtons = [
  (Icons.arrow_back, ScrcpyKeycode.back),
  (Icons.circle_outlined, ScrcpyKeycode.home),
  (Icons.menu, ScrcpyKeycode.appSwitch),
];
