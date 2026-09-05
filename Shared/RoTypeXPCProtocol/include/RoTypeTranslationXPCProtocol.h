#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define ROTYPE_TRANSLATION_SERVICE_NAME @"im.roarkai.inputmethod.Luoke.translation"

@protocol RoTypeTranslationXPCProtocol
// v2: a versioned string-only payload; v1 remains available for old clients.
- (void)translateCandidateWithSessionID:(NSString *)sessionID
                            generation:(int64_t)generation
                               request:(NSDictionary<NSString *, NSString *> *)request
                             withReply:(void (^)(int64_t generation,
                                                 NSString * _Nullable direction,
                                                 NSString * _Nullable translatedSource,
                                                 NSString * _Nullable translatedText,
                                                 NSError * _Nullable error))reply
    NS_SWIFT_NAME(translateCandidate(sessionID:generation:request:withReply:));

- (void)translateWithSessionID:(NSString *)sessionID
                   generation:(int64_t)generation
                      rawInput:(NSString *)rawInput
                   sourceText:(NSString *)sourceText
                    withReply:(void (^)(int64_t generation,
                                        NSString * _Nullable direction,
                                        NSString * _Nullable translatedSource,
                                        NSString * _Nullable translatedText,
                                        NSError * _Nullable error))reply
    NS_SWIFT_NAME(translate(sessionID:generation:rawInput:sourceText:withReply:));

- (void)cancelWithSessionID:(NSString *)sessionID
          throughGeneration:(int64_t)generation
    NS_SWIFT_NAME(cancel(sessionID:throughGeneration:));

- (void)recordControllerInput;

- (void)controllerInputGenerationWithReply:(void (^)(int64_t generation,
                                                       NSError * _Nullable error))reply
    NS_SWIFT_NAME(controllerInputGeneration(reply:));
@end

NS_ASSUME_NONNULL_END
