import SwiftUI

/// Plain-language explanation of a metric, shown in a popover from the ⓘ button.
struct Hint {
    struct Level {
        let range: String
        let label: String
        let color: Color
    }

    let title: String
    let body: String
    var scale: [Level] = []
    var tip: String? = nil
}

struct HintButton: View {
    var hint: Hint
    @State private var shown = false
    @State private var hover = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(hover || shown ? Theme.accent : Theme.text3)
            .contentShape(Circle())
            .onHover { hover = $0 }
            .onTapGesture { shown.toggle() }
            .help(hint.title)
            .popover(isPresented: $shown, arrowEdge: .bottom) { HintCard(hint: hint) }
    }
}

struct HintCard: View {
    var hint: Hint

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hint.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            Text(hint.body).font(.system(size: 12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            if !hint.scale.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(hint.scale.enumerated()), id: \.offset) { _, l in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(l.color).frame(width: 4, height: 16)
                            Text(l.range).font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(Theme.text)
                                .frame(width: 96, alignment: .leading)
                            Text(l.label).font(.system(size: 12)).foregroundStyle(Theme.text2)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            if let tip = hint.tip {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Theme.warn).font(.system(size: 11))
                    Text(tip).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(width: 330)
        .background(Theme.bgRaised)
        .environment(\.colorScheme, .dark)
    }
}

enum Hints {
    static let score = Hint(
        title: "Общая оценка сети",
        body: "Сводный балл от 0 до 100. Складывается из силы сигнала, уровня помех, диапазона и стандарта, загрузки канала соседями, защиты и (после теста) задержки до роутера.",
        scale: [.init(range: "85–100", label: "Отлично", color: Theme.good),
                .init(range: "70–84", label: "Хорошо", color: Theme.fair),
                .init(range: "50–69", label: "Средне", color: Theme.warn),
                .init(range: "0–49", label: "Плохо", color: Theme.bad)],
        tip: "Нажмите «Тест задержки», чтобы оценка учла стабильность связи с роутером.")

    static let signal = Hint(
        title: "Сила сигнала (RSSI)",
        body: "Насколько громко Mac «слышит» роутер, в dBm. Значения отрицательные: чем ближе к нулю, тем лучше. Каждые −3 dBm — это вдвое меньше мощности.",
        scale: [.init(range: "−30…−55", label: "Отличный", color: Theme.good),
                .init(range: "−56…−67", label: "Хороший, хватит для видео", color: Theme.fair),
                .init(range: "−68…−75", label: "Средний, бывают провалы", color: Theme.warn),
                .init(range: "ниже −75", label: "Слабый, обрывы", color: Theme.bad)],
        tip: "Метки на полоске — пороги −67 и −55 dBm.")

    static let snr = Hint(
        title: "Сигнал / шум (SNR)",
        body: "Разница между сигналом роутера и фоновым радиошумом. Даже сильный сигнал бесполезен, если вокруг много помех. Именно SNR определяет, какую скорость сможет выбрать Wi‑Fi.",
        scale: [.init(range: "> 40 dB", label: "Чистый эфир", color: Theme.good),
                .init(range: "25–40 dB", label: "Нормально", color: Theme.fair),
                .init(range: "15–25 dB", label: "Помехи режут скорость", color: Theme.warn),
                .init(range: "< 15 dB", label: "Связь нестабильна", color: Theme.bad)])

    static let rate = Hint(
        title: "Скорость канала",
        body: "Скорость, о которой Mac и роутер договорились по воздуху (PHY rate). Это потолок, а не реальная скорость интернета: на деле получается примерно 60–70% от этого числа.",
        tip: "Потолок Wi‑Fi 6 с двумя антеннами: ≈1200 Мбит/с при 80 МГц и ≈2400 Мбит/с при 160 МГц. Достигается только вблизи роутера в чистом эфире.")

    static let traffic = Hint(
        title: "Трафик сейчас",
        body: "Сколько данных прямо сейчас проходит через Wi‑Fi: ↓ входящий (загрузка) и ↑ исходящий (отдача). Это реальная нагрузка, а не тест скорости. Те же цифры видны в строке меню.")

    static let channel = Hint(
        title: "Канал и ширина",
        body: "Wi‑Fi делит диапазон на каналы. Если соседи на том же или пересекающемся канале, роутеры вынуждены делить эфир по очереди. Ширина (20/40/80/160 МГц) — это «полосность дороги»: шире — быстрее, но выше шанс столкнуться с соседями.",
        tip: "DFS — каналы 52–144: часто свободны, но роутер обязан покинуть их при обнаружении радара. На 2,4 ГГц каналы 12–13 не видят устройства для рынка США и часть старой техники — надёжнее 1, 6 или 11.")

    static let standard = Hint(
        title: "Стандарт Wi‑Fi",
        body: "Поколение протокола, по которому идёт связь. Wi‑Fi 6 (802.11ax) лучше справляется с множеством устройств и экономит батарею. Wi‑Fi 6E — то же, но ещё и в чистом диапазоне 6 ГГц.",
        scale: [.init(range: "Wi‑Fi 7 · be", label: "Новейший, 2024", color: Theme.good),
                .init(range: "Wi‑Fi 6/6E · ax", label: "Современный, 2019", color: Theme.fair),
                .init(range: "Wi‑Fi 5 · ac", label: "Устаревает, 2013", color: Theme.warn),
                .init(range: "Wi‑Fi 4 · n", label: "Медленно, 2009", color: Theme.bad)],
        tip: "Полная расшифровка всех стандартов и что поддерживает ваш Mac — на вкладке «Устройство».")

    static let signalChart = Hint(
        title: "График сигнала",
        body: "Синяя линия — сила сигнала за последние минуты, серый пунктир — уровень шума. Чем больше расстояние между ними, тем лучше. Оранжевая линия −67 dBm — рекомендуемый минимум для звонков и видео.",
        tip: "Походите с ноутбуком по квартире и посмотрите, где сигнал проседает.")

    static let breakdown = Hint(
        title: "Из чего складывается оценка",
        body: "Каждая полоска — отдельный фактор от 0 до 100%. Самая короткая полоска — главное, что тянет оценку вниз. С неё и стоит начинать.")

    static let latency = Hint(
        title: "Задержка и потери",
        body: "Отправляем 20 пингов до роутера и до 1.1.1.1. Показана медиана: Wi‑Fi в режиме энергосбережения иногда даёт одиночные всплески, и медиана их не учитывает. Если плохо уже до роутера, проблема в Wi‑Fi. Если до роутера хорошо, а до интернета плохо, проблема у провайдера.",
        scale: [.init(range: "до роутера < 5 мс", label: "Отлично", color: Theme.good),
                .init(range: "5–15 мс", label: "Нормально", color: Theme.fair),
                .init(range: "> 15 мс", label: "Помехи / слабый сигнал", color: Theme.warn),
                .init(range: "потери > 1%", label: "Плохо для звонков и игр", color: Theme.bad)])

    static let spectrum = Hint(
        title: "Как читать спектр",
        body: "Каждый «горб» — одна сеть. По горизонтали — частота (номера каналов), ширина горба — ширина канала сети. Высота — сила её сигнала у вас. Ваша сеть выделена синим со звёздочкой. Где горбы перекрываются, сети мешают друг другу.",
        tip: "Наведите курсор на график — появится список сетей на этой частоте.")

    static let channelLoad = Hint(
        title: "Загрузка каналов",
        body: "Для каждого канала считаем «давление соседей»: каждая сеть учитывается с весом по силе её сигнала и по тому, насколько её полоса перекрывает канал.",
        scale: [.init(range: "0.0–0.3", label: "Свободно", color: Theme.good),
                .init(range: "0.3–1.0", label: "Терпимо", color: Theme.fair),
                .init(range: "1.0–2.0", label: "Тесно", color: Theme.warn),
                .init(range: "> 2.0", label: "Перегружен", color: Theme.bad)],
        tip: "Канал выбирают в настройках роутера: Wi‑Fi → 2,4/5 ГГц → Канал.")
}
