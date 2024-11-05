
/**
 * @module typedarray-polyfill
 */

var methods = ['values', 'sort', 'some', 'slice', 'reverse', 'reduceRight', 'reduce', 'map', 'keys', 'lastIndexOf', 'join', 'indexOf', 'includes', 'forEach', 'find', 'findIndex', 'copyWithin', 'filter', 'entries', 'every', 'fill'];

if (typeof Int8Array !== 'undefined') {
    for (var i = methods.length; i--;) {
        var method = methods[i];
        if (!Int8Array.prototype[method]) Int8Array.prototype[method] = Array.prototype[method];
    }
}
if (typeof Uint8Array !== 'undefined') {
    for (var i = methods.length; i--;) {
        var method = methods[i];
        if (!Uint8Array.prototype[method]) Uint8Array.prototype[method] = Array.prototype[method];
    }
}
if (typeof Uint8ClampedArray !== 'undefined') {
    for (var i = methods.length; i--;) {
        var method = methods[i];
        if (!Uint8ClampedArray.prototype[method]) Uint8ClampedArray.prototype[method] = Array.prototype[method];
    }
}
if (typeof Int16Array !== 'undefined') {
    for (var i = methods.length; i--;) {
        var method = methods[i];
        if (!Int16Array.prototype[method]) Int16Array.prototype[method] = Array.prototype[method];
    }
}
if (typeof Uint16Array !== 'undefined') {
    for (var i = methods.length; i--;) {
        var method = methods[i];
        if (!Uint16Array.prototype[method]) Uint16Array.prototype[method] = Array.prototype[method];
    }
}
if (typeof Int32Array !== 'undefined') {
    for (var i = methods.length; i--;) {
        var method = methods[i];
        if (!Int32Array.prototype[method]) Int32Array.prototype[method] = Array.prototype[method];
    }
}
if (typeof Uint32Array !== 'undefined') {
    for (var i = methods.length; i--;) {
        var method = methods[i];
        if (!Uint32Array.prototype[method]) Uint32Array.prototype[method] = Array.prototype[method];
    }
}
if (typeof Float32Array !== 'undefined') {
    for (var i = methods.length; i--;) {
        var method = methods[i];
        if (!Float32Array.prototype[method]) Float32Array.prototype[method] = Array.prototype[method];
    }
}
if (typeof Float64Array !== 'undefined') {
    for (var i = methods.length; i--;) {
        var method = methods[i];
        if (!Float64Array.prototype[method]) Float64Array.prototype[method] = Array.prototype[method];
    }
}
if (typeof TypedArray !== 'undefined') {
    for (var i = methods.length; i--;) {
        var method = methods[i];
        if (!TypedArray.prototype[method]) TypedArray.prototype[method] = Array.prototype[method];
    }
}