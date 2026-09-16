#import "POIResultsCardView.h"
#import "../Services/LocalizationManager.h"
#import <objc/runtime.h>

@interface POIResultsCardView ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) NSArray<MKPointAnnotation *> *annotations;
@end

@implementation POIResultsCardView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.96];
        self.layer.cornerRadius = 16.0;
        self.layer.borderColor = [[UIColor colorWithWhite:0.3 alpha:0.7] CGColor];
        self.layer.borderWidth = 1.0;
        self.layer.shadowColor = [[UIColor blackColor] CGColor];
        self.layer.shadowOpacity = 0.6;
        self.layer.shadowRadius = 10.0;
        self.layer.shadowOffset = CGSizeMake(0, -3);
        self.hidden = YES;

        // Intestazione
        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, frame.size.width - 80, 28)];
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:16.0];
        [self addSubview:self.titleLabel];

        // Pulsante Chiudi
        self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.closeButton.frame = CGRectMake(frame.size.width - 52, 6, 40, 30);
        self.closeButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
        [self.closeButton setTitleColor:[UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];
        self.closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:18.0];
        [self.closeButton addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.closeButton];

        // Scroll orizzontale per le card dei POI
        self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 38, frame.size.width, frame.size.height - 42)];
        self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.scrollView.showsHorizontalScrollIndicator = NO;
        self.scrollView.alwaysBounceHorizontal = YES;
        [self addSubview:self.scrollView];
    }
    return self;
}

- (void)showWithAnnotations:(NSArray<MKPointAnnotation *> *)annotations
               categoryName:(NSString *)categoryName
            currentLocation:(CLLocation *)currentLocation {
    self.annotations = annotations;
    NSString *fmt = NLString(@"POI_NEARBY", @"%@ %lu nelle vicinanze");
    self.titleLabel.text = [NSString stringWithFormat:fmt, categoryName, (unsigned long)annotations.count];

    // Rimuovi card precedenti
    for (UIView *sub in self.scrollView.subviews) {
        [sub removeFromSuperview];
    }

    // Ordina per distanza dalla posizione corrente
    NSMutableArray *sortedAnnotations = [annotations mutableCopy];
    if (currentLocation) {
        [sortedAnnotations sortUsingComparator:^NSComparisonResult(MKPointAnnotation *a, MKPointAnnotation *b) {
            CLLocation *locA = [[CLLocation alloc] initWithLatitude:a.coordinate.latitude longitude:a.coordinate.longitude];
            CLLocation *locB = [[CLLocation alloc] initWithLatitude:b.coordinate.latitude longitude:b.coordinate.longitude];
            CLLocationDistance dA = [currentLocation distanceFromLocation:locA];
            CLLocationDistance dB = [currentLocation distanceFromLocation:locB];
            return dA < dB ? NSOrderedAscending : NSOrderedDescending;
        }];
    }

    CGFloat cardW = 200.0;
    CGFloat cardH = self.scrollView.bounds.size.height - 8;
    CGFloat x = 12.0;

    for (NSUInteger i = 0; i < sortedAnnotations.count; i++) {
        MKPointAnnotation *ann = sortedAnnotations[i];
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(x, 4, cardW, cardH)];
        card.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
        card.layer.cornerRadius = 12.0;
        card.layer.borderColor = [[UIColor colorWithWhite:0.32 alpha:0.6] CGColor];
        card.layer.borderWidth = 1.0;

        // Nome
        UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, cardW - 20, 20)];
        nameLabel.text = ann.title ?: @"Punto di interesse";
        nameLabel.textColor = [UIColor whiteColor];
        nameLabel.font = [UIFont boldSystemFontOfSize:13.0];
        nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:nameLabel];

        // Indirizzo
        UILabel *addrLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 26, cardW - 20, 16)];
        addrLabel.text = ann.subtitle ?: @"";
        addrLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        addrLabel.font = [UIFont systemFontOfSize:11.0];
        addrLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:addrLabel];

        // Distanza
        UILabel *distLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 44, cardW - 20, 18)];
        if (currentLocation) {
            CLLocation *poiLoc = [[CLLocation alloc] initWithLatitude:ann.coordinate.latitude longitude:ann.coordinate.longitude];
            CLLocationDistance dist = [currentLocation distanceFromLocation:poiLoc];
            if (dist < 1000) {
                distLabel.text = [NSString stringWithFormat:@"📍 %.0f m", dist];
            } else {
                distLabel.text = [NSString stringWithFormat:@"📍 %.1f km", dist / 1000.0];
            }
        } else {
            distLabel.text = @"📍 --";
        }
        distLabel.textColor = [UIColor colorWithRed:0.2 green:0.7 blue:1.0 alpha:1.0];
        distLabel.font = [UIFont boldSystemFontOfSize:12.0];
        [card addSubview:distLabel];

        // Pulsante Naviga
        UIButton *navBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        navBtn.frame = CGRectMake(10, cardH - 36, cardW - 20, 28);
        navBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.65 blue:0.35 alpha:1.0];
        navBtn.layer.cornerRadius = 8.0;
        [navBtn setTitle:NLString(@"START_NAVIGATION", @"▶ Naviga") forState:UIControlStateNormal];
        [navBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        navBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
        objc_setAssociatedObject(navBtn, "poi_index", @(i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [navBtn addTarget:self action:@selector(navigateToPOI:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:navBtn];

        [self.scrollView addSubview:card];
        x += cardW + 10;
    }

    self.scrollView.contentSize = CGSizeMake(x, cardH);

    self.hidden = NO;
    self.alpha = 0;
    [UIView animateWithDuration:0.3 animations:^{
        self.alpha = 1.0;
    }];
}

- (void)navigateToPOI:(UIButton *)sender {
    NSNumber *idx = objc_getAssociatedObject(sender, "poi_index");
    NSUInteger i = [idx unsignedIntegerValue];
    if (i < self.annotations.count) {
        MKPointAnnotation *ann = self.annotations[i];
        if ([self.delegate respondsToSelector:@selector(poiResultsCardView:didSelectNavigateToPOI:)]) {
            [self.delegate poiResultsCardView:self didSelectNavigateToPOI:ann];
        }
        [self dismiss];
    }
}

- (void)dismiss {
    [UIView animateWithDuration:0.25 animations:^{
        self.alpha = 0;
    } completion:^(BOOL finished) {
        self.hidden = YES;
    }];
}

@end
