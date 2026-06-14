// SPEC: domain.uitool.boot
// The boot dylib's image-load shim exports no public API — its only job is the
// ObjC +load in Loader.m, which the runtime invokes when the dylib is loaded. This
// header exists solely to satisfy SwiftPM's public-headers requirement for a
// C-family target.
