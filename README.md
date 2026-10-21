# 📦 GravitySDK for iOS

`GravitySDK` — это мощный инструмент для интеграции персонализированного контента, отслеживания взаимодействия пользователей и отображения кампаний в мобильных iOS-приложениях. Он позволяет получать контент по шаблонам, отслеживать события и отображать контент в различных форматах (модальное окно, полноэкранный режим, bottom sheet).

## 📚 Оглавление

- [✨ Возможности](#возможности)
- [🚀 Установка](#установка)
- [⚙️ Инициализация](#инициализация)
- [🔧 Дополнительные параметры initialize](#дополнительные-параметры-initialize)
- [🎨 ProductViewBuilder — кастомизация отображения продуктов](#productviewbuilder--кастомизация-отображения-продуктов)
- [🧑 Пользователь и настройки](#пользователь-и-настройки)
- [📄 Отслеживание и события](#отслеживание-и-события)
- [📈 Взаимодействие](#взаимодействие)
- [🧩 Получение контента](#получение-контента)
- [🖼️ Отображение контента](#отображение-контента)
- [❗ Обработка ошибок](#обработка-ошибок)

## Возможности

- Инициализация SDK с ключом API и параметрами секции
- Настройка контента и прокси
- Отслеживание посещений страниц и пользовательских событий
- Получение контента по шаблону
- Отображение контента в:
    - Модальном окне
    - Bottom sheet
    - Полноэкранном режиме
    - Snackbar
    - Bottom sheet с рядом товаров
- Отправка взаимодействий с контентом и продуктами

## Установка

Добавь зависимость через Swift Package Manager:

```
https://github.com/Gravity-Field/gravity-sdk-ios.git
```

Или в `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Gravity-Field/gravity-sdk-ios.git", from: "1.1.0")
]
```

## Инициализация

Для работы SDK необходимо провести базовую инициализацию, передав параметры `apiKey` и `section`. Их можно найти в личном кабинете.

```swift
GravitySDK.initialize(
    apiKey: "your-api-key",
    section: "your-section-id"
)
```

## Настройка демоприложения

Для `Example/GravitySDKDemo` задайте `GRAVITY_DEMO_API_KEY` и `GRAVITY_DEMO_SECTION`
в переменных окружения локальной схемы Xcode (Edit Scheme → Run → Arguments →
Environment Variables). Без этих значений приложение покажет инструкцию настройки
и не будет отправлять запросы в SDK. Не сохраняйте ключ в общей `.xcscheme` в Git.

Используйте отдельный демонстрационный проект и ключ с минимально необходимыми
правами. Ключ, доступный мобильному клиенту, можно извлечь на устройстве;
локальная настройка защищает репозиторий, но не делает ключ серверным секретом.
Если ключ уже был закоммичен, замените его: переписывание истории не удаляет
чужие клоны и сохранённые версии diff в GitLab.

## Дополнительные параметры initialize

```swift
GravitySDK.initialize(
    apiKey: String,
    section: String,
    gravityEventCallback: GravityEventCallback? = nil,
    productViewBuilder: ProductViewBuilder? = nil,
    productFilter: ProductFilter? = nil,
    logLevel: LogLevel = .error,
)
```

- `productViewBuilder` — кастомная отрисовка карточек продуктов
- `gravityEventCallback` — колбэк, вызываемый при трекинге событий
- `productFilter` — фильтр продуктов
- `logLevel` — уровень логирования SDK. По умолчанию `.error` — видны только ошибки

## ProductViewBuilder — кастомизация отображения продуктов

ProductViewBuilder — это интерфейс, предназначенный для кастомной отрисовки карточек продуктов в рамках кампаний. Он предоставляет гибкость, позволяя разработчику контролировать внешний вид товаров, интегрированных в кампанию, чтобы они соответствовали стилю приложения.

**Зачем это нужно?**

Часть кампаний содержит продукты (например, рекомендованные товары, акции, предложения). Чтобы эти карточки визуально вписывались в интерфейс приложения, необходимо передать в SDK свою реализацию ProductViewBuilder.

Если не указать productViewBuilder, продукты не будут отображены.

## Пользователь и настройки

```swift
GravitySDK.instance.setUser(userId: "user-id", sessionId: "session-id")

GravitySDK.instance.setOptions(
    options: Options(...),
    contentSettings: ContentSettings(...),
    proxyUrl: url,
)
```

## Отслеживание и события

```swift
GravitySDK.instance.trackView(
    pageContext: PageContext(...),
    viewController: viewController,
)

GravitySDK.instance.triggerEvent(
    events: [TriggerEvent(...)],
    pageContext: PageContext(...),
    viewController: viewController,
)
```

## Взаимодействие

```swift
GravitySDK.instance.sendContentEngagement(engagement: ContentImpressionEngagement(...))
GravitySDK.instance.sendProductEngagement(engagement: ProductClickEngagement(...))
```

## Получение контента

```swift
let response = await GravitySDK.instance.getContentBySelector(
    selector: "selector",
    pageContext: PageContext(...),
)
```

## Отображение контента

Отображение контента происходит автоматически после вызова одного из методов: `trackView`
или `triggerEvent`

## Обработка ошибок

Если любой публичный метод SDK вызван до `GravitySDK.initialize(...)`, вызов безопасно игнорируется:
в лог пишется сообщение об ошибке, а методы, возвращающие значение, возвращают `nil`

Проверить состояние инициализации можно так:

```swift
if GravitySDK.isInitialized {
    // SDK готов к работе
}
```

## Подготовка in-app перед показом

`initialize` принимает необязательный `inAppPreparation`. Обработчик получает контент и кампанию, асинхронно проверяет товары и возвращает контент для показа либо `nil`, чтобы пропустить этот in-app и перейти к следующей кампании.

```swift
GravitySDK.initialize(
    apiKey: "your-api-key",
    section: "your-section-id",
    productViewBuilder: reviewIntegration.productViewBuilder,
    inAppPreparation: reviewIntegration.preparation()
)
```

[Пример ReviewPromptIntegration](Example/GravitySDKDemo/GravitySDKDemo/ReviewPromptIntegration.swift) включает интерфейс клиентского API eligibility, карточку с кнопкой «Оставить отзыв» и обновление локального статуса через `didSubmitReview(sku:)` после успешной отправки отзыва. Карточка вызывает `dismissInApp`; SDK закрывает sheet и затем вызывает `onOpenReview` для маршрутизации приложения. В demo-приложении пример подключён через [ReviewPromptCoordinator](Example/GravitySDKDemo/GravitySDKDemo/ReviewPromptCoordinator.swift): `DemoReviewEligibilityAPI` проверяет локальный `ReviewStatusStore`, который сохраняется между запусками. Это демонстрация клиентской фильтрации, а не серверное API отзывов. В приложении клиента замените эту проверку обращением к своему API и обновляйте локальный статус только после успешной отправки отзыва.

Обработчик можно написать напрямую:

В примере задайте `selector` кампании отзывов и `fallbackProductViewBuilder` для остальных кампаний. Если у кампании нет selector, ограничьте обработку по `campaign.payload.first?.campaignId`.

```swift
let preparation = InAppPreparation(timeout: 5) { content, campaign in
    guard campaign.selector == "purchase-reviews" else { return content }
    let skus = content.products?.slots?.compactMap { $0.item["sku"] as? String } ?? []
    guard !skus.isEmpty else { return nil }
    let eligible = try await reviewAPI.eligibleSkus(Array(Set(skus)))
    return content.filteringProducts { slot in
        guard let sku = slot.item["sku"] as? String else { return false }
        return eligible.contains(sku)
    }
}
```

Порядок: `/choose` → существующий синхронный `productFilter` → content-loaded tracking → задержка кампании → `inAppPreparation` → повторная проверка возможности показа → UI и impression-события. Обработчик применяется к автоматическому показу после `trackView`/`triggerEvent`, а также при `open_step`. Получение через `getContentBy*` и inline-виджеты сохраняют прежнее поведение.

- Без обработчика нет ожидания API. Для других кампаний верните исходный `content`.
- `filteringProducts` сохраняет исходные слоты, порядок, tracking-данные и метаданные; пустой результат возвращает `nil`. Пустые блоки в других кампаниях не запрещены.
- Таймаут по умолчанию — 5 секунд. Ошибка, таймаут или некорректный timeout (не положительный, не конечный либо больше часа) пропускают in-app. Используйте отменяемый async API; не блокируйте поток.
- После ожидания проверяются экран, presentation lock и ревизия пользователя. `setUser` и `lockPresentation` инвалидируют ожидающий показ, даже если затем восстановлено прежнее состояние. При навигации внутри одного контроллера блокируйте показ через `lockPresentation`. После разблокировки нужен новый view/trigger.
- Пропущенный in-app не отправляет impression/visible impression; content-loaded сохраняет семантику загрузки. Удалённые слоты не монтируются. В своём builder отправляйте клик через `sendProductEngagement`.
- Используйте recently purchased без fallback на непокупавшиеся товары. Правила доставки/отмены/возврата проверяет API eligibility. Запрашивайте кандидатов с запасом: SDK не восполняет удалённые товары.
- Перед запуском проверьте пользователя в `/choose` (отдельное исправление EGO-246). Клиентский статус отзывов должен принадлежать текущему аккаунту.

## Закрытие in-app из обычного ProductViewBuilder

Публичный `dismissInApp(contentId:completion:)` закрывает только показанный SDK in-app с указанным `contentId`: modal, bottom sheet, full screen или snackbar. Inline-реквиджеты не закрываются. Тип и сигнатура `ProductViewBuilder` не меняются.

В обработчике кнопки сначала отправьте product click, затем запросите закрытие:

```swift
GravitySDK.instance.sendProductEngagement(engagement:
    ProductClickEngagement(slot: slot, content: content, campaign: campaign))
GravitySDK.instance.dismissInApp(contentId: content.contentId) { dismissed in
    if dismissed { onOpenReview(sku) }
}
```

При успешном закрытии completion вызывается на UI-потоке после анимации и удаления in-app с результатом `true`. Если контент не показан, уже закрывается/закрыт или отсутствует, completion получает `false` без ожидания закрытия. При повторном клике пока идёт закрытие возвращается `false`, чтобы не открывать форму дважды. Close-событие отправляет SDK один раз; вручную отправлять его не нужно. Если нужен переход и при отсутствии in-app, обработайте `false` в своей навигации.

Метод сам не отправляет product click. Кнопку отзывов по-прежнему выбирайте по кампании и используйте текущий builder для обычных рекомендаций.
