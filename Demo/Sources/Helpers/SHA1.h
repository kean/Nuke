// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>

NSString *
_nuke_sha1(const char *data, uint32_t length) {
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data, (CC_LONG)length, hash);

    char utf8[2 * CC_SHA1_DIGEST_LENGTH + 1];
    char *temp = utf8;
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        snprintf(temp, 3, "%02x", hash[i]);
        temp += 2;
    }
    return [NSString stringWithUTF8String:utf8];
}
