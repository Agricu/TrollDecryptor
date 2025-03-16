// NetCustomTableViewCell.m
#import "NetCustomTableViewCell.h"

@interface NetCustomTableViewCell()
///@property (nonatomic, strong) UILabel *versionLabel;
@end

@implementation NetCustomTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // 创建版本标签
        _versionLabel = [[UILabel alloc] init];
        _versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _versionLabel.textAlignment = NSTextAlignmentLeft;
        
        // 配置文本样式
        ///UIColor *secondaryColor = [UIColor colorWithRed:0.55 green:0.55 blue:0.57 alpha:1.0];
        UIFont *primaryFont = [UIFont systemFontOfSize:15.0];
        UIFont *secondaryFont = [UIFont systemFontOfSize:12.0];
        
        // 主标题
        self.textLabel.font = primaryFont;
        //self.textLabel.textColor = secondaryColor;
        
        // 副标题
        self.detailTextLabel.font = secondaryFont;
        //self.detailTextLabel.textColor = secondaryColor;
        
        // 版本标签
        _versionLabel.font = secondaryFont;
       // _versionLabel.textColor = secondaryColor;
        
        // 添加到内容视图
        [self.contentView addSubview:_versionLabel];
        
        // 禁用系统imageView的自动布局
        self.imageView.translatesAutoresizingMaskIntoConstraints = YES;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // 布局常量
    CGFloat leftMargin = 30.0;       // 整体左侧边距
    CGFloat iconSize = 50.0;         // 图标尺寸
    CGFloat iconTextSpacing = 20.0;  // 图标与文本间距
    CGFloat textSpacing = 1.0;       // 文本垂直间距
    CGFloat textHeight = 18.0;       // 单行文本高度
    CGFloat rightMargin = 16.0;      // 右侧边距
    
    // 容器尺寸计算
    CGRect contentFrame = self.contentView.bounds;
    
    // 计算文本总高度 (3个文本 + 2个间距)
    CGFloat totalTextHeight = (3 * textHeight) + (2 * textSpacing);
    
    // 垂直居中偏移量
    CGFloat containerY = (CGRectGetHeight(contentFrame) - MAX(iconSize, totalTextHeight)) / 2;
    
    // 图标布局（带边框）
        CGFloat iconY = containerY + (totalTextHeight - iconSize) / 2;
        self.imageView.frame = CGRectMake(leftMargin, iconY, iconSize, iconSize);
        self.imageView.layer.cornerRadius = iconSize / 5.0;
        self.imageView.layer.masksToBounds = YES;
        self.imageView.layer.borderColor = [UIColor colorWithRed:0.85 green:0.85 blue:0.85 alpha:1.0].CGColor; // 边框色
        self.imageView.layer.borderWidth = 0.3; // 边框粗细
        self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    
    // 文本布局参数
    CGFloat textX = leftMargin + iconSize + iconTextSpacing;
    CGFloat textWidth = CGRectGetWidth(contentFrame) - textX - rightMargin;
    
    // 文本垂直布局
    CGFloat textStartY = containerY;
    
    // 主标题
    self.textLabel.frame = CGRectMake(textX, textStartY, textWidth, textHeight);
    
    // 版本标签
    self.versionLabel.frame = CGRectMake(textX,
                                        textStartY + textHeight + textSpacing,
                                        textWidth,
                                        textHeight);
    
    // 副标题
    self.detailTextLabel.frame = CGRectMake(textX,
                                           textStartY + 2 * (textHeight + textSpacing),
                                           textWidth,
                                           textHeight);
    
    // 强制左对齐（系统默认可能不同）
    self.textLabel.textAlignment = NSTextAlignmentLeft;
    self.detailTextLabel.textAlignment = NSTextAlignmentLeft;
    self.versionLabel.textAlignment = NSTextAlignmentLeft;
}

@end
