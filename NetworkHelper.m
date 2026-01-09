#import "NetworkHelper.h"
#import <CommonCrypto/CommonDigest.h>
#import "ReportHelper.h"
#import <AppsFlyerLib/AppsFlyerLib.h>

#define kCodeFieldName @"code"
#define kBodyFieldName @"data"
#define kMsgFieldName @"msg"
#define kMessageFieldName @"message"
#define kPageSize @15
#define kNotNetWork -9911
#define kNotNetWorkDesc kLocalizedString(@"network_error",nil)

const NSString * SDK_Version2 = @"1.0.0";

@interface NetworkHelper()
@property (nonatomic, strong) NSMutableArray<NSString *> *apiDomains;
@end

@implementation NetworkHelper{
    NSURLSessionTask *_tokenLoginTask;
    
}

static NetworkHelper *_instance = nil;
AFHTTPSessionManager *networkManager;

- (AFHTTPSessionManager *)getManager
{
    return networkManager;
}

//- (NSString *)getApiDomain
//{
//    return [Tools configModel].api_url;
//}

- (NSString *)getApiVersion
{
    return [Tools configModel].api_version;
}

- (NSString *)getApiRegion
{
    return [Tools configModel].api_region;
}

- (NSString *)getLanguage
{
    return [Tools getLanguageStr];
}

- (NSString *)getWebDomain
{
    return [Tools configModel].api_url;
}

- (NSMutableArray<NSString *> *)apiDomains {
    if (!_apiDomains) {
        NSMutableArray *apis = [NSMutableArray arrayWithArray:[Tools configModel].apis];
        [apis insertObject:[Tools configModel].api_url atIndex:0];
        _apiDomains = [apis mutableCopy];
    }
    return _apiDomains;
}

+ (instancetype)shared
{
    static dispatch_once_t onceToken;
    @synchronized(self){
        dispatch_once(&onceToken, ^{
            _instance = [[super allocWithZone:nil] init] ;
            networkManager = [AFHTTPSessionManager manager];
            networkManager.responseSerializer = [AFJSONResponseSerializer new];
            networkManager.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"application/json", @"text/json", @"text/javascript",@"text/html",@"text/plain", nil];
            [networkManager.requestSerializer willChangeValueForKey:@"timeoutInterval"];
            networkManager.requestSerializer.timeoutInterval = 20.0f;
            [networkManager.requestSerializer didChangeValueForKey:@"timeoutInterval"];
            [networkManager.requestSerializer setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
//            [networkManager.requestSerializer setValue:[Tools configModel].access_key forHTTPHeaderField:@"access-key"];
            
           
        });}
    
    return _instance;
}

+ (id)allocWithZone:(struct _NSZone *)zone
{
    return [NetworkHelper shared];
}

- (id)copyWithZone:(struct _NSZone *)zone
{
    return [NetworkHelper shared];
}

- (void)xm_promoteDomainOnSuccess:(NSString *)domain {
    if (!domain || self.apiDomains.count == 0) return;

    if (![self.apiDomains.firstObject isEqualToString:domain]) {
        [self.apiDomains removeObject:domain];
        [self.apiDomains insertObject:domain atIndex:0];

        [[XMSDKAPI shared] sdklog:
            [NSString stringWithFormat:@"[DomainMTF] %@ -> first", domain]];
    }
}

- (NSURLSessionTask *)getWith:(NSString *)url parameters:(NSDictionary *)parameters progress:(void(^)(NSProgress *downloadProgress))progress success:(void(^)(NSURLSessionDataTask *task, id responseObject))success failure:(void(^)(NSURLSessionDataTask *task, NSError *error))failure
{
//    NSMutableDictionary *request = [NSMutableDictionary dictionaryWithDictionary:parameters];
//    [request setValue:[self getApiRegion] forKey:@"region"];
//    [request setValue:[self getLanguage] forKey:@"language"];
//    
//    [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"start=>%@%@%@%@" ,[self getApiDomain], @"" ,[self getApiVersion], url]];
//    [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"headers2=>%@",[networkManager.requestSerializer HTTPRequestHeaders]]];
//    [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"params=>%@",request]];
//    return [networkManager GET:[NSString stringWithFormat:@"%@%@%@", [self getApiDomain], [self getApiVersion], url] parameters:request progress:progress success:success failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
//        if (![Tools isConnectionAvailable]) {
//            failure(task, [NSError errorWithDomain:kBundleName code:kNotNetWork userInfo:[NSDictionary dictionaryWithObject:kNotNetWorkDesc forKey:@"NSLocalizedDescription"]]);
//        }else{
//            failure(task, error);
//        }
//    }];
    
    NSMutableDictionary *request = [NSMutableDictionary dictionaryWithDictionary:parameters ?: @{}];
    request[@"region"]   = [self getApiRegion];
    request[@"language"] = [self getLanguage];

    NSArray<NSString *> *domains = [self.apiDomains copy];
    if (domains.count == 0) {
        if (failure) {
            NSError *error = [NSError errorWithDomain:kBundleName
                                                 code:-10001
                                             userInfo:@{NSLocalizedDescriptionKey:@"No available api domain"}];
            failure(nil, error);
        }
        return nil;
    }

    return [self xm_getWithDomains:domains
                             index:0
                               url:url
                        parameters:request
                          progress:progress
                           success:success
                           failure:failure];
}

- (NSURLSessionTask *)xm_getWithDomains:(NSArray<NSString *> *)domains
                                  index:(NSInteger)index
                                    url:(NSString *)url
                             parameters:(NSDictionary *)parameters
                               progress:(void(^)(NSProgress *downloadProgress))progress
                                success:(void(^)(NSURLSessionDataTask *task, id responseObject))success
                                failure:(void(^)(NSURLSessionDataTask *task, NSError *error))failure
{
    NSString *domain = domains[index];

    NSString *fullURL = [NSString stringWithFormat:@"%@%@%@",
                         domain,
                         [self getApiVersion],
                         url];

    [[XMSDKAPI shared] sdklog:
        [NSString stringWithFormat:@"[GET][%ld/%ld] %@",
         (long)(index + 1),
         (long)domains.count,
         fullURL]];

    return [networkManager GET:fullURL
                     parameters:parameters
                       progress:progress
                        success:^(NSURLSessionDataTask *task, id responseObject) {
                            // ✅ 成功前置（MTF）
                            [self xm_promoteDomainOnSuccess:domain];
                            if (success) {
                                success(task, responseObject);
                            }
                        }
                        failure:^(NSURLSessionDataTask *task, NSError *error) {

                            BOOL canRetry = [self xm_canRetryWithError:error];
                            BOOL hasNext  = (index + 1 < domains.count);

                            if (canRetry && hasNext) {
                                [[XMSDKAPI shared] sdklog:
                                    [NSString stringWithFormat:@"[GET] retry next domain (%ld)",
                                     (long)(index + 2)]];
                                
                                [self xm_getWithDomains:domains
                                                  index:index + 1
                                                    url:url
                                             parameters:parameters
                                               progress:progress
                                                success:success
                                                failure:failure];
                            } else {
                                if (failure) {
                                    failure(task, error);
                                }
                            }
                        }];
}

- (NSURLSessionTask *)postWith:(NSString *)url parameters:(NSDictionary *)parameters body:(void(^)(id<AFMultipartFormData> formData))body progress:(void(^)(NSProgress *downloadProgress))progress success:(void(^)(NSURLSessionDataTask *task, id responseObject))success failure:(void(^)(NSURLSessionDataTask *task, NSError *error))failure
{
    return [self postWith:url module:@"" parameters:parameters body:body progress:progress success:success failure:failure];
}

- (NSURLSessionTask *)postWith:(NSString *)url module:(NSString *)modulle parameters:(NSDictionary *)parameters body:(void(^)(id<AFMultipartFormData> formData))body progress:(void(^)(NSProgress *downloadProgress))progress success:(void(^)(NSURLSessionDataTask *task, id responseObject))success failure:(void(^)(NSURLSessionDataTask *task, NSError *error))failure
{
    NSMutableDictionary *request = [NSMutableDictionary dictionaryWithDictionary:parameters];
    request = [self addGeneralParameters:request];

    NSArray<NSString *> *domains = [self.apiDomains copy];
    if (domains.count == 0) {
        if (failure) {
            NSError *error = [NSError errorWithDomain:kBundleName
                                                 code:-10001
                                             userInfo:@{
                                                 NSLocalizedDescriptionKey : @"No available api domain"
                                             }];
            failure(nil, error);
        }
        return nil;
    }

    // 从第 0 个域名开始尝试
    return [self xm_postWithDomains:domains
                              index:0
                                url:url
                             module:modulle
                          parameters:request
                                body:body
                            progress:progress
                             success:success
                             failure:failure];
    
//
//    NSMutableDictionary *request = [NSMutableDictionary dictionaryWithDictionary:parameters];
//    request = [self addGeneralParameters:request];
//    
//    [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"start=>%@%@%@%@" ,[self getApiDomain], @"" ,[self getApiVersion], url]];
//    [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"headers3=>%@",[networkManager.requestSerializer HTTPRequestHeaders]]];
//    [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"params=>%@",request]];
//    
//    return [networkManager POST:[NSString stringWithFormat:@"%@%@%@%@?region=%@&language=%@" ,[self getApiDomain], modulle ,[self getApiVersion], url, [self getApiRegion], [self getLanguage]] parameters:request constructingBodyWithBlock:body progress:progress success:success failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
//        if (![Tools isConnectionAvailable]) {
//            failure(task, [NSError errorWithDomain:kBundleName code:kNotNetWork userInfo:[NSDictionary dictionaryWithObject:kNotNetWorkDesc forKey:@"NSLocalizedDescription"]]);
//        }else{
//            failure(task, error);
//        }
//    }];
}

- (BOOL)xm_canRetryWithError:(NSError *)error {

    // 没网，换域名也没用
    if (![Tools isConnectionAvailable]) {
        return NO;
    }

    // 只处理真正的网络传输错误
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case NSURLErrorTimedOut:
            case NSURLErrorCannotFindHost:
            case NSURLErrorCannotConnectToHost:
            case NSURLErrorDNSLookupFailed:
            case NSURLErrorNetworkConnectionLost:
            case NSURLErrorNotConnectedToInternet:
                return YES;

            default:
                return NO;
        }
    }

    // 其他 domain（比如自定义 error），默认不 retry
    return NO;
}

- (NSURLSessionTask *)xm_postWithDomains:(NSArray<NSString *> *)domains
                                   index:(NSInteger)index
                                     url:(NSString *)url
                                  module:(NSString *)module
                               parameters:(NSDictionary *)parameters
                                     body:(void(^)(id<AFMultipartFormData> formData))body
                                 progress:(void(^)(NSProgress *downloadProgress))progress
                                  success:(void(^)(NSURLSessionDataTask *task, id responseObject))success
                                  failure:(void(^)(NSURLSessionDataTask *task, NSError *error))failure
{
    NSString *domain = domains[index];

    NSString *fullURL = [NSString stringWithFormat:@"%@%@%@%@?region=%@&language=%@",
                         domain,
                         module ?: @"",
                         [self getApiVersion],
                         url,
                         [self getApiRegion],
                         [self getLanguage]];

    [[XMSDKAPI shared] sdklog:
        [NSString stringWithFormat:@"[POST][%ld/%ld] %@",
         (long)(index + 1),
         (long)domains.count,
         fullURL]];

    return [networkManager POST:fullURL
                      parameters:parameters
       constructingBodyWithBlock:body
                        progress:progress
                         success:^(NSURLSessionDataTask *task, id responseObject) {
                            // ✅ 成功前置（MTF）
                            [self xm_promoteDomainOnSuccess:domain];
                            if (success) {
                                success(task, responseObject);
                            }
                         }
                         failure:^(NSURLSessionDataTask *task, NSError *error) {

                             BOOL canRetry = [self xm_canRetryWithError:error];
                             BOOL hasNext = (index + 1 < domains.count);

                             if (canRetry && hasNext) {
                                 [[XMSDKAPI shared] sdklog:
                                     [NSString stringWithFormat:@"[POST] retry next domain (%ld)",
                                      (long)(index + 2)]];
                                 
                                 [self xm_postWithDomains:domains
                                                    index:index + 1
                                                      url:url
                                                   module:module
                                                parameters:parameters
                                                      body:body
                                                  progress:progress
                                                   success:success
                                                   failure:failure];
                             } else {
                                 if (failure) {
                                     failure(task, error);
                                 }
                             }
                         }];
}

//- (NSURLSessionTask *)putWith:(NSString *)url parameters:(NSDictionary *)parameters success:(void(^)(NSURLSessionDataTask *task, id responseObject))success failure:(void(^)(NSURLSessionDataTask *task, NSError *error))failure
//{
//    return [self putWith:url module:@"" parameters:parameters success:success failure:failure];
//}
//
//- (NSURLSessionTask *)putWith:(NSString *)url module:(NSString *)modulle parameters:(NSDictionary *)parameters success:(void(^)(NSURLSessionDataTask *task, id responseObject))success failure:(void(^)(NSURLSessionDataTask *task, NSError *error))failure
//{
//    NSMutableDictionary *request = [NSMutableDictionary dictionaryWithDictionary:parameters];
//    request = [self addGeneralParameters:request];
//    
//    [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"start=>%@%@%@%@" ,[self getApiDomain], @"" ,[self getApiVersion], url]];
//    [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"headers4=>%@",[networkManager.requestSerializer HTTPRequestHeaders]]];
//    [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"params=>%@",request]];
//    
//    return [networkManager PUT:[NSString stringWithFormat:@"%@%@%@%@?region=%@&language=%@" ,[self getApiDomain], modulle ,[self getApiVersion], url, [self getApiRegion], [self getLanguage]] parameters:request success:success failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
//        if (![Tools isConnectionAvailable]) {
//            failure(task, [NSError errorWithDomain:kBundleName code:kNotNetWork userInfo:[NSDictionary dictionaryWithObject:kNotNetWorkDesc forKey:@"NSLocalizedDescription"]]);
//        }else{
//            failure(task, error);
//        }
//    }];
//}

- (NSMutableDictionary *)addGeneralParameters:(NSMutableDictionary *)params
{
    NSMutableDictionary *base = [[ReportHelper shared] getGeneralParameters:@{}];
    for (id key in params) {
        [base setValue:params[key] forKey:key];
    }
    return base;
}

- (NSString *)sign:(NSMutableDictionary *)params
{
    NSArray *sortArray = [[params allKeys] sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        return [obj1 compare:obj2 options:NSNumericSearch];
    }];
    
    NSMutableString *paramStr = [[NSMutableString alloc] init];
    for (id key in sortArray) {
        NSString *value = [NSString stringWithFormat:@"%@=%@&",key, [params objectForKey:key]];
        [paramStr appendString:value];
    }
    [paramStr deleteCharactersInRange:(NSRange){[paramStr length] - 1, 1}];
//    [paramStr appendString:[Tools configModel].access_secret];
    return [self getMd5WithString:paramStr];
}

- (NSString *)getMd5WithString:(NSString *)str
{
    const char *cStr = [str UTF8String];
    unsigned char result[16];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), result); // This is the md5 call
    return [[NSString stringWithFormat:
             @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
             result[0], result[1], result[2], result[3],
             result[4], result[5], result[6], result[7],
             result[8], result[9], result[10], result[11],
             result[12], result[13], result[14], result[15]
             ] uppercaseString];
}

- (void)dealResponse:(id)responseObject correct:(void(^)(id body))correct incorrect:(void(^)(NSError *error))incorrect
{
    NSInteger responseCode = [[responseObject objectForKey:kCodeFieldName] intValue];
    if (responseCode == 0)
    {
        correct([responseObject objectForKey:kBodyFieldName]);
    }
    else
    {
        NSDictionary *msgInfo = nil;
        NSString *message = [[responseObject objectForKey:kMessageFieldName] stringValue];
        if (message != nil && message.length > 0) {
            msgInfo = [NSDictionary dictionaryWithObject:message forKey:@"NSLocalizedDescription"];
        }else{
            msgInfo = [NSDictionary dictionaryWithObject:[self getTipsMsg:responseCode param: [responseObject objectForKey:kMsgFieldName]] forKey:@"NSLocalizedDescription"];
        }
        
        NSError *result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:msgInfo];
//        switch (responseCode) {
//            case 1001://請求出錯
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"req_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 1002://請求服務器出錯
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"req_head_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 1003://未知錯誤
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"unkonw_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//
//            case 2001://帐号已存在
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"login_account_exist_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 2002://帐号不存在
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"login_account_no_exist_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 2003://帐号/密码不正确
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"login_account_pwd_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 2004://帳號已停用
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"login_account_stop_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 2005://token 無效
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"login_token_invalid", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 2006://獲取蘋果公鑰失敗
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"fetch_apple_key_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 2007://沒有匹配的公鑰
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"no_match_key_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 2008://付費點不存在/未配置
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"product_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 2009://付費點不一致
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"product_no_match_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 2010://已存在相同的訂單號
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"duplicate_order_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 2011://谷歌access token 刷新失敗
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"google_token_refresh_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 2012://支付驗證失敗
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"pay_verify_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 2013://訂單不存在
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"order_no_exist_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 2014://Facebook 商務平台令牌獲取失敗
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"facebook_token_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//            case 2015://非遊客帳號
//                result = [NSError errorWithDomain:kBundleName code:responseCode userInfo:[NSDictionary dictionaryWithObject:kLocalizedString(@"no_guest_error", nil) forKey:@"NSLocalizedDescription"]];
//                break;
//
//            default:
//                break;
//        }
        incorrect(result);
    }
}

#pragma mark - <Api>
- (RACSignal *)gameInit
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        [self getWith:@"/initialize" parameters:@{
            @"app_id": @([Tools configModel].app_id)
        } progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
            [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"gameInit result=>%@",responseObject]];
            @strongify(self)
            if (responseObject[@"data"] != nil) {
                self.i18n = responseObject[@"data"][@"i18n"];
            }
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"gameInit error=>%@",[error description]]];
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"gameInit error=>%@",[error description]]];
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)loginAccount:(NSString *)account password:(NSString *)password deviceId:(nonnull NSString *)deviceId maintenance:(BOOL)isMain
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        [self postWith:@"/member/signin" parameters:@{
            @"account": account,
            @"password": password,
            @"device_id": deviceId,
            @"app_id": @([Tools configModel].app_id),
            @"maintenance" : @(isMain)
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
            [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"loginAccount result=>%@",responseObject]];
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"loginAccount error=>%@",[error description]]];
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            [[XMSDKAPI shared] sdklog:[NSString stringWithFormat:@"loginAccount error=>%@",[error description]]];
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)bindAccount:(NSString *)account password:(NSString *)password deviceId:(nonnull NSString *)deviceId bindingToken:(NSString *)bindingToken
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        [self postWith:@"/member/bind/member" parameters:@{
            @"account": account,
            @"password": password,
            @"device_id": deviceId,
            @"app_id": @([Tools configModel].app_id),
            @"token": bindingToken
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
                NSLog(@"bindAccount result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"bindAccount error=>%@",[error localizedDescription]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"bindAccount error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (void)cancelTokenLogin
{
    if (_tokenLoginTask) {
        [_tokenLoginTask cancel];
    }
}

- (RACSignal *)report:(GamePlayerInfoModel *)p token:(NSString *)token
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        NSMutableDictionary * param = [[p mj_keyValues] mutableCopy];
        param[@"token"] = token;
        
        self->_tokenLoginTask = [self postWith:@"/report/role" parameters:param body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
                NSLog(@"report result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"report error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"report error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)loginToken:(NSString *)token deviceId:(NSString *)deviceId maintenance: (BOOL)isMain
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        self->_tokenLoginTask = [self postWith:@"/member/verify" parameters:@{
            @"token": token,
            @"device_id": deviceId,
            @"app_id": @([Tools configModel].app_id),
            @"maintenance" : @(isMain)
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
                NSLog(@"loginToken result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"loginToken error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"loginToken error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)bindFacebook:(NSString *)token deviceId:(NSString *)deviceId bindingToken:(NSString *)bindingToken
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        self->_tokenLoginTask = [self postWith:@"/member/bind/facebook_jwt" parameters:@{
            @"device_id": deviceId,
            @"id_token": token,
            @"app_id": @([Tools configModel].app_id),
            @"token": bindingToken
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
                NSLog(@"bindFacebook result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"bindFacebook error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"bindFacebook error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)loginFacebook:(NSString *)token deviceId:(NSString *)deviceId maintenance:(BOOL)isMain
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        self->_tokenLoginTask = [self postWith:@"/member/facebook_jwt" parameters:@{
            @"device_id": deviceId,
            @"id_token": token,
            @"app_id": @([Tools configModel].app_id),
            @"maintenance" : @(isMain)
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
                NSLog(@"loginFacebook result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"loginFacebook error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"loginFacebook error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)bindGoogle:(NSString *)token deviceId:(NSString *)deviceId account:(NSString *)account bindingToken:(NSString *)bindingToken
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        self->_tokenLoginTask = [self postWith:@"/member/bind/google_jwt" parameters:@{
            @"device_id": deviceId,
            @"id_token": token,
            @"app_id": @([Tools configModel].app_id),
            @"token": bindingToken,
            @"account": account
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
                NSLog(@"bindGoogle result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"bindGoogle error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"bindGoogle error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)loginGoogle:(NSString *)token deviceId:(NSString *)deviceId account:(NSString *)account maintenance:(BOOL)isMain
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        self->_tokenLoginTask = [self postWith:@"/member/google_jwt" parameters:@{
            @"device_id": deviceId,
            @"id_token": token,
            @"app_id": @([Tools configModel].app_id),
            @"account": account,
            @"maintenance" : @(isMain)
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
                NSLog(@"loginGoogle result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"loginGoogle error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"loginGoogle error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}
- (RACSignal *)bindApple:(NSString *)token deviceId:(NSString *)deviceId bindingToken:(NSString *)bindingToken
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        self->_tokenLoginTask = [self postWith:@"/member/bind/apple" parameters:@{
            @"device_id": deviceId,
            @"id_token": token,
            @"app_id": @([Tools configModel].app_id),
            @"token": bindingToken,
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
                NSLog(@"bindApple result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"bindApple error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"bindApple error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)loginApple:(NSString *)token deviceId:(NSString *)deviceId maintenance:(BOOL)isMain
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        self->_tokenLoginTask = [self postWith:@"/member/apple" parameters:@{
            @"device_id": deviceId,
            @"id_token": token,
            @"app_id": @([Tools configModel].app_id),
            @"maintenance" : @(isMain)
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
                NSLog(@"loginApple result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"loginApple error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"loginApple error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)loginNaver:(NSString *)token deviceId:(NSString *)deviceId maintenance:(BOOL)isMain
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        self->_tokenLoginTask = [self postWith:@"/member/naver" parameters:@{
            @"device_id": deviceId,
            @"id_token": token,
            @"app_id": @([Tools configModel].app_id),
            @"maintenance" : @(isMain)
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
                NSLog(@"loginNaver result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"loginNaver error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"loginNaver error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)bindNaver:(NSString *)token deviceId:(NSString *)deviceId bindingToken:(NSString *)bindingToken
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        self->_tokenLoginTask = [self postWith:@"/member/bind/naver" parameters:@{
            @"device_id": deviceId,
            @"id_token": token,
            @"app_id": @([Tools configModel].app_id),
            @"token": bindingToken,
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
                NSLog(@"bindApple result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"bindApple error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"bindApple error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)loginGuest:(NSString *)deviceId maintenance:(BOOL)isMain
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        self->_tokenLoginTask = [self postWith:@"/member/tourist" parameters:@{
            @"device_id": deviceId,
            @"app_id": @([Tools configModel].app_id),
            @"maintenance" : @(isMain)
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            
                NSLog(@"loginGuest result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"loginGuest error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"XMSDK: loginGuest error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)reportFirebaseToken:(NSString *)token firebaseToken:(NSString *)firebaseToken
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        [self postWith:@"/report/firebase_token" parameters:@{
            @"app_id": @([Tools configModel].app_id),
            @"firebase_token": firebaseToken,
            @"token": token
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"reportFirebaseToken result=>%@",responseObject);

            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"reportFirebaseToken error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"reportFirebaseToken error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)genOrder:(NSString *)token tradeSN:(NSString *)tradeSN productId:(NSString *)productId serverId:(NSString *)serverId roleName:(NSString *)roleName roleId:(NSString *)roleId extra:(NSString *)extra
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        self->_tokenLoginTask = [self postWith:@"/payment/order" parameters:@{
            @"trade_sn": tradeSN,
            @"app_id": @([Tools configModel].app_id),
            @"token": token,
            @"product_id": productId,
            @"server_id": serverId,
            @"role_name": roleName,
            @"role_id": roleId,
            @"extra": extra == nil ? @"" : extra,
            @"region": [XMSDKAPI shared].region?:@""
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"genOrder result=>%@",responseObject);

            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                 NSLog(@"XMSDK: genOrder error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"XMSDK: genOrder error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)registerAccount:(NSString *)account password:(NSString *)password deviceId:(nonnull NSString *)deviceId
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        [self postWith:@"/member/signup" parameters:@{
            @"account": account,
            @"password": password,
            @"device_id": deviceId,
            @"app_id": @([Tools configModel].app_id)
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"registerAccount result=>%@",responseObject);

            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"registerAccount error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"registerAccount error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)userActive:(NSString *)token
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        [self getWith:@"/user/active" parameters:@{
            @"token": token
        } progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"userActive result=>%@",responseObject);

            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                 NSLog(@"userActive error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"userActive error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)historyAccounts:(NSString *)deviceId
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        [self postWith:@"/member/history_accounts" parameters:@{
            @"device_id": deviceId,
            @"app_id": @([Tools configModel].app_id)
        } body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"historyAccounts result=>%@",responseObject);

            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                 NSLog(@"historyAccounts error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"historyAccounts error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)verifyReceipt:(NSString *)receipt orderNo:(NSString *)orderNo transactionId:(NSString *)transaction_id productId:(nonnull NSString *)productId
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        
        NSDictionary *params = @{
            @"receipt": receipt ? : @"",
            @"order_sn": orderNo ? : @"",
            @"product_id": productId ? : @"",
            @"transaction_id": transaction_id ? : @"",
            @"token": [Tools mineInfo].token ? : @""
        };
        
        [self postWith:@"/payment/apple" module:@"" parameters:params body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"apple_iap result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"apple_iap error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"apple_iap error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}


- (RACSignal *)uploadFailedEvent:(NSString *)event receipt:(NSString *)receipt orderNo:(NSString *)orderNo transactionId:(NSString *)transaction_id productId:(nonnull NSString *)productId sessionId:(NSString *)sessionId error:(NSString *)errorMsg
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        
        NSDictionary *params = @{
            @"event": event ?: @"",
            @"receipt": receipt ? : @"",
            @"order_sn": orderNo ? : @"",
            @"product_id": productId ? : @"",
            @"transaction_id": transaction_id ? : @"",
            @"token": [Tools mineInfo].token ? : @"",
            @"device_id": [Tools getDeviceId],
            @"session_id": sessionId,
            @"error": errorMsg ?: @""
        };
        
        [self postWith:@"/log/apple/iap/failed" module:@"" parameters:params body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"uploadFailedReceipt result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"uploadFailedReceipt error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"uploadFailedReceipt error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)uploadIAPLog:(NSDictionary *)logDict
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        
        [self postWith:@"/log/apple/iap" module:@"" parameters:logDict body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"uploadIAPLog result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"uploadIAPLog error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"uploadIAPLog error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)memberDelete:(NSString *)token code:(NSString *)code
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        
        NSDictionary *params = @{
            @"app_id": @([Tools configModel].app_id),
            @"device_id": [Tools getDeviceId],
            @"code": code,
            @"token": token
        };
        
        [self postWith:@"/member/ask_delete" module:@"" parameters:params body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"memberDelete result=>%@",responseObject);

            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"memberDelete error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"memberDelete error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)memberDelete2:(NSString *)token code:(NSString *)code
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        
        NSDictionary *params = @{
            @"app_id": @([Tools configModel].app_id),
            @"device_id": [Tools getDeviceId],
            @"code": code,
            @"token": token
        };
        
        [self postWith:@"/member/ask_delete2" module:@"" parameters:params body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"memberDelete2 result=>%@",responseObject);

            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"memberDelete error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"memberDelete error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

- (RACSignal *)deleteResume:(NSString *)token
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        
        NSDictionary *params = @{
            @"app_id": @([Tools configModel].app_id),
            @"device_id": [Tools getDeviceId],
            @"token": token
        };
        
        [self postWith:@"/member/ask_resume" module:@"" parameters:params body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"deleteResume result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"deleteResume error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"deleteResume error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}




- (NSMutableURLRequest *)getUserCenterUrl:(NSString *)baseUrl
{
    NSString *afid = [[AppsFlyerLib shared] getAppsFlyerUID];

    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"token": [Tools mineInfo].token,
        @"region": [self getApiRegion],
        @"language": [self getLanguage],
        @"app_id": @([Tools configModel].app_id),
        @"device_id": [Tools getDeviceId],
        @"afid": afid != nil ? afid : @"",
    }];
    if (![Tools firebaseModel].isEmpty) {
        FirebaseModel *firebaseModel = [Tools firebaseModel];
        [dict setValue:firebaseModel.logFirebaseApInstanceId forKey:@"ga_app_instance_id"];
//        if (firebaseModel.logFirebaseSessionId != 0) {
//            [dict setValue:@(firebaseModel.logFirebaseSessionId) forKey:@"ga_session_id"];
//        }
    }
    NSMutableString *url = [NSMutableString stringWithFormat:@"%@?", baseUrl];
    for (id key in dict) {
        [url appendFormat:@"%@=%@&",key,dict[key]];
    }
    return [self getRequest:url sign:[self sign:dict]];
}

- (NSMutableURLRequest *)getPayUrl:(PayInfoModel *)args
{
    @try {
        NSMutableDictionary *dict = [args mj_keyValues];
        [dict setValue:[Tools mineInfo].token forKey:@"token"];
        dict = [self addGeneralParameters:dict];
        NSMutableString *url = [NSMutableString stringWithFormat:@"%@/%@?", [self getWebDomain], @"payments/view"];
        for (id key in dict) {
            [url appendFormat:@"%@=%@&",key,dict[key]];
        }
        return [self getRequest:url sign:[self sign:dict]];
    } @catch (NSException *exception) {
        NSLog(@"------出错了 start ----------");
        NSLog(@"报错了:%@", [exception description]);
        NSLog(@"------出错了 end ----------");
    } @finally {
        
    }
    return nil;
}

- (NSMutableURLRequest *)getRequest:(NSString *)url sign:(NSString *)sign
{
    NSString *encodedString = (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                                                    (CFStringRef)url,
                                                                                                    (CFStringRef)@"!$&'()*+,-./:;=?@_~%#[]",
                                                                                                    NULL,
                                                                                                    kCFStringEncodingUTF8));
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:encodedString]];
//    if (!request.allHTTPHeaderFields[@"access-key"]) {
////        [request setValue:[Tools configModel].access_key forHTTPHeaderField:@"access-key"];
//    }
//    [request setValue:sign forHTTPHeaderField:@"sign"];
    return request;
}


- (NSString *)getTipsMsg: (NSInteger)code param: (NSArray *)param;
{
    NSDictionary * dic = _i18n[[NSString stringWithFormat:@"%ld",(long)code]];
    if ([dic allKeys].count != 0) {
        NSString * key = @"en";
        NSString * lang = [Tools configModel].language;

        if (lang != nil) {
            if ([lang isEqual:@"vn"] || [lang isEqual:@"vi"]) {
                key = @"vn";
            } else if ([lang isEqual:@"zh"]) {
                key = @"zh";
            } else if ([lang isEqual:@"en"]) {
                key = @"en";
            }else{
                key = lang;
            }
        }
        NSString * value = dic[key];
        if (value != nil) {
            if (code != 1019) {
                NSArray * array = [value componentsSeparatedByString:@"%@"];
                if (array.count == 1) {
                    NSLog(@"SDK接口错误信息 = %@", value);
                    return value;
                }
                if (![param isKindOfClass:[NSArray class]]) {
                    NSLog(@"SDK接口错误信息 = %@", value);
                    return value;
                }
                if (array.count != param.count +1 ) {
                    NSLog(@"SDK接口错误信息 = %@", value);
                    return value;
                }
                NSString * backStr = @"";
                for (int i = 0; i < MIN(array.count, param.count); i++) {
                    backStr = [NSString stringWithFormat:@"%@%@",backStr, array[i]];
                    backStr = [NSString stringWithFormat:@"%@%@",backStr, param[i]];
                }
                if (array.lastObject != nil && [array.lastObject isKindOfClass:[NSString class] ]) {
                    backStr = [NSString stringWithFormat:@"%@%@", backStr, array.lastObject];
                }
                NSLog(@"SDK接口错误信息 = %@", backStr);
                return backStr;
            } else {
                return [self stringWithFormat: value args: param];
            }
        }
    }
    return [NSString stringWithFormat:@"%@(%ld)", kLocalizedString(@"error", nil), (long)code];
}

- (NSString *)stringWithFormat:(NSString *)format args:(NSArray *)args
{
    switch (args.count) {
        case 1:
            return [NSString stringWithFormat:format, args[0]];
        case 2:
            return [NSString stringWithFormat:format, args[0], args[1]];
            
        default:
            return format;
    }
    return format;
}

- (RACSignal *)location
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        [self getWith:@"/user/location" parameters: nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"userLocation result=>%@",responseObject);

            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"userLocation error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"userLocation error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];

}

- (RACSignal *)reportCrash:(NSString *)crash
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self)
        [self postWith:@"/logs/error" parameters:@{@"content": crash} body:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"reportCrash result=>%@",responseObject);
            @strongify(self)
            [self dealResponse:responseObject correct:^(id body) {
                [subscriber sendNext:body];
                [subscriber sendCompleted];
            } incorrect:^(NSError *error) {
                NSLog(@"reportCrash error=>%@",[error description]);
                [subscriber sendError:error];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"reportCrash error=>%@",[error description]);
            [subscriber sendError:error];
        }];
        return nil;
    }];
}

@end
