// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

#import <Foundation/Foundation.h>

/// Produces 160-bit hash value using SHA-1 algorithm.
/// - returns: String containing 160-bit hash value expressed as a 40 digit
/// hexadecimal number.
extern NSString *
_nuke_sha1(const char *data, uint32_t length);
