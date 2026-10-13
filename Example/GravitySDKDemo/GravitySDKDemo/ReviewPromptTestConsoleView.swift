import Foundation
import GravitySDK
import SwiftUI

/// Manual + scenario test console for `ReviewPromptIntegration` (EGO-247).
///
/// Exercises the real integration code against synthetic campaign content, with no dependency
/// on a live backend campaign: press "Запустить проверки" for pass/fail scenario checks, or
/// "Получить рекомендации" to run the eligibility pipeline and render the resulting product cards
/// with the real review button wired to `sendProductEngagement` / `dismissInApp`.
struct ReviewPromptTestConsoleView: View {
    private static let selector = ReviewPromptCoordinator.selector

    @StateObject private var model = ReviewPromptTestConsoleModel(selector: selector)
    @ObservedObject private var coordinator = ReviewPromptCoordinator.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                scenarioSection
                recommendationsSection
                realCampaignSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Review Prompt Test Console")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scenarioSection: some View {
        ConsoleCard(title: "Автоматические проверки", systemImage: "checkmark.seal") {
            Text("Фильтрация, исключение уже отправленных отзывов, пустые/ошибочные ответы, чужие кампании.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Запустить проверки") {
                Task { await model.runScenarios() }
            }
            .buttonStyle(.bordered)
            .disabled(model.isRunningScenarios)

            if model.isRunningScenarios {
                ProgressView()
            }

            if !model.scenarioResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.scenarioResults) { result in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.passed ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name).font(.caption.weight(.medium))
                                Text(result.detail).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 4)

                let passed = model.scenarioResults.filter { $0.passed }.count
                Text("\(passed)/\(model.scenarioResults.count) пройдено")
                    .font(.caption.bold())
                    .foregroundColor(passed == model.scenarioResults.count ? .green : .red)
            }
        }
    }

    private var recommendationsSection: some View {
        ConsoleCard(title: "Демо рекомендаций", systemImage: "bag") {
            Text("Синтетические SKU-1…5: SKU-2/SKU-4 недоступны для отзыва, SKU-5 уже отправлен.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Получить рекомендации") {
                Task { await model.loadRecommendations() }
            }
            .buttonStyle(.bordered)
            .disabled(model.isLoadingRecommendations)

            if model.isLoadingRecommendations {
                ProgressView()
            }

            if let error = model.recommendationsError {
                Text(error).font(.caption).foregroundColor(.red)
            }

            if !model.recommendedSlots.isEmpty {
                Text("Клик по карточке шлёт ProductClickEngagement и вызывает dismissInApp; здесь нет реального in-app, поэтому оно вернёт false и форма не откроется — это защитное поведение, не баг.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(model.recommendedSlots, id: \.slotId) { entry in
                            model.integration.productViewBuilder.build(
                                slot: entry.slot,
                                content: entry.content,
                                campaign: entry.campaign
                            )
                        }
                    }
                }
            } else if model.didLoadRecommendations {
                Text("Нет рекомендованных товаров — все отфильтрованы.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LogView(lines: model.log)
        }
    }

    private var realCampaignSection: some View {
        ConsoleCard(title: "Реальная кампания", systemImage: "antenna.radiowaves.left.and.right") {
            Text("\(ReviewPromptCoordinator.campaignId) · selector \"\(Self.selector)\" · триггер Page load / Search page")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Button("Получить и показать по selector") {
                    Task { await coordinator.fetchAndPreviewBySelector() }
                }
                .buttonStyle(.borderedProminent)
                Text("Детерминировано: без конкуренции с другими кампаниями на том же триггере.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !coordinator.preview.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(coordinator.preview) { entry in
                            SelectorPreviewCard(entry: entry, coordinator: coordinator)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Button("Запустить триггер (trackView, Search page)") {
                    coordinator.triggerRealCampaign()
                }
                .buttonStyle(.bordered)
                Text("Настоящий bottom sheet SDK, но конкурирует по приоритету с другими кампаниями на этом триггере — если видите не ту кампанию, используйте кнопку выше.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Button("Сбросить статус отзывов", role: .destructive) {
                    coordinator.resetReviewStatus()
                }
                .buttonStyle(.bordered)
                Text("Отправленные отзывы сохраняются в UserDefaults и переживают перезапуск — сброс только для повторного тестирования демо.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            LogView(lines: coordinator.log)
        }
    }
}

/// Section container giving the console a consistent card look instead of a flat wall of text.
private struct ConsoleCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// Bounded, scrollable log output instead of an ever-growing plain list.
private struct LogView: View {
    let lines: [String]

    var body: some View {
        if !lines.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2.monospaced())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 110)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
        }
    }
}

/// Product card for the "Получить и показать по selector" preview. Visually matches the real
/// `ReviewPromptIntegration` card, but routes the click through `reviewFromPreview` instead of the
/// real `ProductViewBuilder`, since there is no live SDK-presented in-app here for `dismissInApp`
/// to close (see `ReviewPromptCoordinator.reviewFromPreview`).
private struct SelectorPreviewCard: View {
    let entry: ReviewPromptCoordinator.PreviewSlot
    let coordinator: ReviewPromptCoordinator

    private var name: String {
        entry.slot.item["name"] as? String ?? (entry.slot.item["sku"] as? String ?? "")
    }
    private var price: String? { entry.slot.item["price"] as? String }
    private var imageURL: URL? {
        (entry.slot.item["image_url"] as? String).flatMap(URL.init(string:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6))
                if let imageURL {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().aspectRatio(contentMode: .fit).padding(6)
                    } placeholder: {
                        ProgressView()
                    }
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(name)
                .font(.caption)
                .lineLimit(2)
                .frame(height: 32, alignment: .top)

            if let price {
                Text("\(price) ₽").font(.caption.bold())
            }

            Button {
                coordinator.reviewFromPreview(slot: entry.slot, content: entry.content, campaign: entry.campaign)
            } label: {
                Text("Оставить отзыв")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .frame(width: 150)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }
}

@MainActor
private final class ReviewPromptTestConsoleModel: ObservableObject {
    struct ScenarioResult: Identifiable {
        let id = UUID()
        let name: String
        let passed: Bool
        let detail: String
    }

    struct SlotEntry {
        let slotId: String
        let slot: Slot
        let content: CampaignContent
        let campaign: Campaign
    }

    /// Only for rendering (`productViewBuilder` needs *some* instance, but doesn't touch `api`).
    /// Actual eligibility checks always use a fresh `makeIntegration` pair — see `runScenarios`/
    /// `loadRecommendations` — so concurrent runs can never share or race on mutable API state.
    let integration: ReviewPromptIntegration
    private let selector: String

    @Published var scenarioResults: [ScenarioResult] = []
    @Published var recommendedSlots: [SlotEntry] = []
    @Published var isRunningScenarios = false
    @Published var isLoadingRecommendations = false
    @Published var didLoadRecommendations = false
    @Published var recommendationsError: String?
    @Published var log: [String] = []

    init(selector: String) {
        self.selector = selector
        self.integration = ReviewPromptIntegration(
            api: TestConsoleReviewAPI(),
            selector: selector,
            fallbackProductViewBuilder: TestConsoleFallbackProductViewBuilder(),
            onOpenReview: { _ in }
        )
    }

    /// A fresh `ReviewPromptIntegration` + `TestConsoleReviewAPI` pair, owned solely by the
    /// caller. Each scenario and `loadRecommendations()` gets its own — sharing one mutable `api`
    /// across concurrent runs (e.g. tapping both buttons back to back) let one run's
    /// `shouldThrow`/`ineligibleSkus` leak into another's in-flight request.
    private func makeIntegration(
        ineligibleSkus: Set<String> = [],
        shouldThrow: Bool = false
    ) -> (integration: ReviewPromptIntegration, api: TestConsoleReviewAPI) {
        let api = TestConsoleReviewAPI(ineligibleSkus: ineligibleSkus, shouldThrow: shouldThrow)
        let integration = ReviewPromptIntegration(
            api: api,
            selector: selector,
            fallbackProductViewBuilder: TestConsoleFallbackProductViewBuilder(),
            onOpenReview: { _ in }
        )
        return (integration, api)
    }

    func runScenarios() async {
        guard !isRunningScenarios else { return }
        isRunningScenarios = true
        defer { isRunningScenarios = false }

        var results: [ScenarioResult] = []

        // 1. Eligible-only subset survives filtering.
        do {
            let (integration, _) = makeIntegration(ineligibleSkus: ["SKU-2"])
            let (content, campaign) = try fixture(skus: ["SKU-1", "SKU-2", "SKU-3"], selector: selector)
            let filtered = try await integration.recommendedContent(for: content, campaign: campaign)
            let skus = filtered?.products?.slots?.compactMap { $0.item["sku"] as? String } ?? []
            let passed = skus == ["SKU-1", "SKU-3"]
            results.append(ScenarioResult(
                name: "Фильтрует по доступности отзыва",
                passed: passed,
                detail: "Ожидали [SKU-1, SKU-3], получили \(skus)"
            ))
        } catch {
            results.append(ScenarioResult(name: "Фильтрует по доступности отзыва", passed: false, detail: "\(error)"))
        }

        // 2. Already-submitted review is excluded even if eligible.
        do {
            let (integration, _) = makeIntegration()
            let (content, campaign) = try fixture(skus: ["SKU-1", "SKU-3"], selector: selector)
            integration.didSubmitReview(sku: "SKU-3")
            let filtered = try await integration.recommendedContent(for: content, campaign: campaign)
            let skus = filtered?.products?.slots?.compactMap { $0.item["sku"] as? String } ?? []
            let passed = skus == ["SKU-1"]
            results.append(ScenarioResult(
                name: "Скрывает уже отправленные отзывы",
                passed: passed,
                detail: "После didSubmitReview(SKU-3) ожидали [SKU-1], получили \(skus)"
            ))
        } catch {
            results.append(ScenarioResult(name: "Скрывает уже отправленные отзывы", passed: false, detail: "\(error)"))
        }

        // 3. No surviving products skips the in-app entirely (nil).
        do {
            let (integration, _) = makeIntegration(ineligibleSkus: ["SKU-1", "SKU-2"])
            let (content, campaign) = try fixture(skus: ["SKU-1", "SKU-2"], selector: selector)
            let filtered = try await integration.recommendedContent(for: content, campaign: campaign)
            results.append(ScenarioResult(
                name: "Пропускает показ, если нет доступных товаров",
                passed: filtered == nil,
                detail: filtered == nil ? "nil, как и ожидалось" : "ожидали nil, получили контент"
            ))
        } catch {
            results.append(ScenarioResult(name: "Пропускает показ, если нет доступных товаров", passed: false, detail: "\(error)"))
        }

        // 4. A campaign with a different selector passes content through untouched.
        do {
            let (integration, api) = makeIntegration()
            let (content, campaign) = try fixture(skus: ["SKU-1", "SKU-2"], selector: "sdk_cart_reco")
            let result = try await integration.recommendedContent(for: content, campaign: campaign)
            let unchanged = result?.products?.slots?.count == content.products?.slots?.count
            let noApiCall = api.requestedSkuBatches.isEmpty
            results.append(ScenarioResult(
                name: "Игнорирует кампании с другим selector",
                passed: unchanged && noApiCall,
                detail: "contentPassedThrough=\(unchanged), apiCalled=\(!noApiCall)"
            ))
        } catch {
            results.append(ScenarioResult(name: "Игнорирует кампании с другим selector", passed: false, detail: "\(error)"))
        }

        // 5. Slots without a recognizable sku skip the in-app without calling the API.
        do {
            let (integration, api) = makeIntegration()
            let (content, campaign) = try fixture(skus: [], selector: selector)
            let result = try await integration.recommendedContent(for: content, campaign: campaign)
            results.append(ScenarioResult(
                name: "Нет SKU — показ пропускается без вызова API",
                passed: result == nil && api.requestedSkuBatches.isEmpty,
                detail: "result=\(result == nil ? "nil" : "non-nil"), apiCalled=\(!api.requestedSkuBatches.isEmpty)"
            ))
        } catch {
            results.append(ScenarioResult(name: "Нет SKU — показ пропускается без вызова API", passed: false, detail: "\(error)"))
        }

        // 6. Duplicate SKUs are de-duplicated before calling the eligibility API.
        do {
            let (integration, api) = makeIntegration()
            let (content, campaign) = try fixture(skus: ["SKU-1", "SKU-1", "SKU-3"], selector: selector)
            _ = try await integration.recommendedContent(for: content, campaign: campaign)
            let requested = Set(api.requestedSkuBatches.last ?? [])
            results.append(ScenarioResult(
                name: "SKU дедуплицируются перед вызовом API",
                passed: requested == ["SKU-1", "SKU-3"],
                detail: "Запрошено: \(requested.sorted())"
            ))
        } catch {
            results.append(ScenarioResult(name: "SKU дедуплицируются перед вызовом API", passed: false, detail: "\(error)"))
        }

        // 7. An API error propagates (InAppPreparation.prepare maps this to a skipped in-app).
        do {
            let (integration, _) = makeIntegration(shouldThrow: true)
            let (content, campaign) = try fixture(skus: ["SKU-1"], selector: selector)
            var threw = false
            do { _ = try await integration.recommendedContent(for: content, campaign: campaign) }
            catch { threw = true }
            results.append(ScenarioResult(
                name: "Ошибка API выбрасывается наверх (используется SDK для пропуска показа)",
                passed: threw,
                detail: threw ? "ошибка выброшена, как и ожидалось" : "ошибка не выброшена"
            ))
        } catch {
            results.append(ScenarioResult(name: "Ошибка API выбрасывается наверх", passed: false, detail: "\(error)"))
        }

        scenarioResults = results
    }

    func loadRecommendations() async {
        guard !isLoadingRecommendations else { return }
        isLoadingRecommendations = true
        recommendationsError = nil
        didLoadRecommendations = false

        let (integration, _) = makeIntegration(ineligibleSkus: ["SKU-2", "SKU-4"])

        do {
            let (content, campaign) = try fixture(
                skus: ["SKU-1", "SKU-2", "SKU-3", "SKU-4", "SKU-5"],
                selector: selector,
                names: ["SKU-1": "Кроссовки", "SKU-2": "Рюкзак", "SKU-3": "Термокружка",
                        "SKU-4": "Наушники", "SKU-5": "Чехол"]
            )
            integration.didSubmitReview(sku: "SKU-5")
            let filtered = try await integration.recommendedContent(for: content, campaign: campaign)
            let slots = filtered?.products?.slots ?? []
            recommendedSlots = slots.enumerated().map { index, slot in
                SlotEntry(
                    slotId: slot.slotId ?? "slot-\(index)",
                    slot: slot,
                    content: filtered ?? content,
                    campaign: campaign
                )
            }
            log.append("recommendedContent → \(recommendedSlots.count) товар(ов): \(recommendedSlots.compactMap { $0.slot.item["sku"] as? String })")
            didLoadRecommendations = true
        } catch {
            recommendationsError = "Ошибка: \(error)"
        }

        isLoadingRecommendations = false
    }

    private func fixture(
        skus: [String],
        selector: String?,
        names: [String: String] = [:]
    ) throws -> (CampaignContent, Campaign) {
        let slotsJSON = skus.enumerated().map { index, sku -> String in
            let name = names[sku] ?? sku
            return """
            {"item":{"sku":"\(sku)","name":"\(name)"},"fallback":false,"strId":1,"slotId":"slot-\(index)"}
            """
        }.joined(separator: ",")

        let json = """
        {"contentId":"console-content","deliveryMethod":"bottom_sheet","contentType":"products",
         "products":{"strategyId":"recently-purchased","fallback":false,"name":"recently purchased",
           "pageNumber":1,"countPages":1,"slots":[\(slotsJSON)]}}
        """
        let content = try JSONDecoder().decode(CampaignContent.self, from: Data(json.utf8))
        return (content, Campaign(selector: selector))
    }
}

/// Configured once at construction and never mutated afterward — each caller (one scenario, or
/// one `loadRecommendations()` run) owns its own instance via `makeIntegration`, so there's no
/// shared mutable state for concurrent runs to race on.
private final class TestConsoleReviewAPI: ReviewEligibilityAPI {
    private let ineligibleSkus: Set<String>
    private let shouldThrow: Bool
    private(set) var requestedSkuBatches: [[String]] = []

    struct SimulatedFailure: Error {}

    init(ineligibleSkus: Set<String> = [], shouldThrow: Bool = false) {
        self.ineligibleSkus = ineligibleSkus
        self.shouldThrow = shouldThrow
    }

    func eligibleSkus(_ skus: [String]) async throws -> Set<String> {
        requestedSkuBatches.append(skus)
        try await Task.sleep(nanoseconds: 150_000_000)
        if shouldThrow { throw SimulatedFailure() }
        return Set(skus).subtracting(ineligibleSkus)
    }
}

private struct TestConsoleFallbackProductViewBuilder: ProductViewBuilder {
    func build(slot: Slot, content: CampaignContent, campaign: Campaign) -> AnyView {
        AnyView(Text(slot.item["name"] as? String ?? ""))
    }
}
