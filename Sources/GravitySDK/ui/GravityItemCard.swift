import SwiftUI

struct GravityItemCard: View {
    let item: Item
    let itemCard: ItemCard
    let onClickCallback: (OnClickModel) -> Void

    private var template: Template {
        itemCard.template
    }
    private var container: Container? {
        template.frameUI?.container
    }
    private var onClick: OnClickModel? {
        container?.onClick
    }
    private var style: Style? {
        container?.style
    }
    private var padding: GravityPadding? {
        style?.padding
    }

    private var horizontalAlignment: HorizontalAlignment {
        style?.contentAlignment?.toHorizontalAlignment() ?? .center
    }
    private var verticalAlignment: Alignment {
        style?.verticalAlignment?.toAlignment() ?? .top
    }

    private var width: CGFloat {
        CGFloat(style?.size?.width ?? 0)
    }

    private var height: CGFloat {
        CGFloat(style?.size?.height ?? 0)
    }

    var body: some View {
        ZStack(alignment: verticalAlignment) {
            VStack(alignment: horizontalAlignment) {
                GravityElementsInCard(
                    elements: template.elements,
                    onClickCallback: onClickCallback,
                    item: item
                )
            }
            .frame(maxWidth: .infinity)
            .applyIf(padding != nil) {
                $0.padding(
                    .init(
                        top: padding!.top,
                        leading: padding!.left,
                        bottom: padding!.bottom,
                        trailing: padding!.right
                    )
                )
            }
        }
        .frame(width: width, height: height)
        .background(
            GravityBackgroundView(
                backgroundColor: style?.backgroundColor ?? Color(.systemBackground),
                backgroundImage: style?.backgroundImage,
                backgroundFit: style?.backgroundFit
            )
        )
        .applyIf(style?.cornerRadius != nil) {
            $0.clipShape(
                RoundedRectangle(cornerRadius: style!.cornerRadius!)
            )
        }
        .applyIf(onClick != nil) {
            $0.contentShape(Rectangle())
                .onTapGesture {
                    onClickCallback(onClick!.copyWith(itemId: item.id))
                }
        }
    }
}
