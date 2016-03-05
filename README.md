[![Build Status](https://travis-ci.org/firebase/firebase-dart.svg?branch=master)](https://travis-ci.org/firebase/firebase-dart)

A Dart wrapper for [Firebase](https://www.firebase.com).

This package contains two implementations of the same ```Firebase``` Dart API:
* The ```JsFirebase``` implementation uses `dart:js` to wrap functionality provided by `firebase.js`
in Dart classes.
* The ```MojoFirebase``` implementation uses [Mojo](https://github.com/domokit/mojo) to wrap functionality provided by Firebase iOS and Android SDKs.

#### Installing

Follow the instructions on the [pub page](http://pub.dartlang.org/packages/firebase#installing).

**The firebase.js library MUST be included for the JavaScript wrapper to work**:

```html
<script src="https://cdn.firebase.com/js/client/2.3.2/firebase.js"></script>
```

