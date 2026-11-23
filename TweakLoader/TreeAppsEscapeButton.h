//
//  TreeAppsEscapeButton.h
//  树应用 —— guest App 内悬浮「切回 TreeApps」按钮
//
//  由 TweakLoader（普通 guest）与 SideStoreSupport（内置 openSSS）共用。
//  header-only：每个 target 各自 import，static 符号互不冲突。
//
//  点击后调用 LCSharedUtils +launchToGuestAppWithClassicMode:0，
//  杀掉当前 guest 进程并拉起宿主 TreeApps（com.kdt.livecontainer）。
//  按钮可拖动，除按钮本体外所有区域点击穿透到底层 App。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - 事件穿透 Window

@interface TreeAppsEscapeWindow : UIWindow
@end

@implementation TreeAppsEscapeWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit) return nil;
    // 只有按钮（及其子视图）接收触摸，其余区域全部穿透
    UIView *view = hit;
    while (view && view != self) {
        if ([view isKindOfClass:[UIButton class]]) return hit;
        view = view.superview;
    }
    return nil;
}

@end

#pragma mark - 按钮 Target

@interface TreeAppsEscapeTarget : NSObject
@end

@implementation TreeAppsEscapeTarget

- (void)tapped {
    Class lc = objc_lookUpClass("LCSharedUtils");
    if (!lc) return;
    ((BOOL (*)(id, SEL, NSUInteger))objc_msgSend)(
        lc, NSSelectorFromString(@"launchToGuestAppWithClassicMode:"), 0);
}

- (void)pan:(UIPanGestureRecognizer *)gesture {
    UIView *button = gesture.view;
    UIView *superview = button.superview;
    if (!superview) return;
    CGPoint delta = [gesture translationInView:superview];
    CGPoint center = button.center;
    center.x += delta.x;
    center.y += delta.y;

    // 限制在屏幕内，留出边缘
    CGFloat half = button.bounds.size.width / 2;
    center.x = MAX(half + 4, MIN(superview.bounds.size.width - half - 4, center.x));
    center.y = MAX(half + 4, MIN(superview.bounds.size.height - half - 4, center.y));
    button.center = center;
    [gesture setTranslation:CGPointZero inView:superview];
}

@end

#pragma mark - 安装

static void TreeAppsEnsureEscapeWindow(UIWindowScene *scene) {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;

    for (UIWindow *existing in scene.windows) {
        if ([existing isKindOfClass:[TreeAppsEscapeWindow class]]) return;
    }

    const CGFloat size = 42;
    CGFloat x = scene.screen.bounds.size.width - size - 14;
    CGFloat y = 110; // 避开状态栏 + 大标题导航栏

    TreeAppsEscapeWindow *window =
        [[TreeAppsEscapeWindow alloc] initWithFrame:scene.screen.bounds];
    window.windowScene = scene;
    window.windowLevel = UIWindowLevelNormal + 1; // 不盖系统弹窗
    window.backgroundColor = UIColor.clearColor;

    UIViewController *host = [UIViewController new];
    host.view.backgroundColor = UIColor.clearColor;
    window.rootViewController = host;

    TreeAppsEscapeTarget *target = [TreeAppsEscapeTarget new];
    objc_setAssociatedObject(window, "treeAppsEscapeTarget", target,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // TreeNewBee: UIWindow 必须被强持有，否则设置 windowScene + hidden=NO 后
    // 立刻被 ARC 释放，悬浮按钮消失。上一版删掉 target.window 的循环引用时
    // 把唯一的强引用也删了 —— 把 window 挂到 scene 上保活（scene 释放时一起释放）。
    objc_setAssociatedObject(scene, "treeNewBeeEscapeWindow", window,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(x, y, size, size);
    button.layer.cornerRadius = size / 2;
    button.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.66];
    button.layer.borderWidth = 0.5;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
    button.layer.shadowColor = UIColor.blackColor.CGColor;
    button.layer.shadowOpacity = 0.35;
    button.layer.shadowRadius = 6;

    UIImage *icon = [UIImage systemImageNamed:@"arrow.backward.to.forward"];
    if (!icon) icon = [UIImage systemImageNamed:@"escape"];
    [button setImage:icon forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.imageEdgeInsets = UIEdgeInsetsMake(11, 11, 11, 11);
    button.accessibilityLabel = @"切回树应用";
    [button addTarget:target action:@selector(tapped)
     forControlEvents:UIControlEventTouchUpInside];
    [button addGestureRecognizer:
        [[UIPanGestureRecognizer alloc] initWithTarget:target action:@selector(pan:)]];

    [host.view addSubview:button];
    window.hidden = NO;
}

static void TreeAppsInstallEscapeButton(void) {
    static id sceneObserver = nil;
    static id appObserver = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sceneObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:UISceneDidActivateNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) {
            TreeAppsEnsureEscapeWindow(note.object);
        }];
        appObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                TreeAppsEnsureEscapeWindow(scene);
            }
        }];
        // +load / constructor 阶段 UIApplication 可能还没就绪，异步补挂
        dispatch_async(dispatch_get_main_queue(), ^{
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                TreeAppsEnsureEscapeWindow(scene);
            }
        });
    });
}
