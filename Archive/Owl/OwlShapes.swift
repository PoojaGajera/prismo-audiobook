import SwiftUI

// Generated from the owl SVG (1000×1000 artboard). Coordinates are normalised to 0…1.

struct OwlBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.50601, 0.79116))
        p.addCurve(to: pt(0.81711, 0.47845), control1: pt(0.68137, 0.78747), control2: pt(0.82066, 0.64747))
        p.addCurve(to: pt(0.49315, 0.17908), control1: pt(0.81356, 0.30943), control2: pt(0.66852, 0.17540))
        p.addCurve(to: pt(0.18206, 0.49179), control1: pt(0.31779, 0.18276), control2: pt(0.17851, 0.32277))
        p.addCurve(to: pt(0.50601, 0.79116), control1: pt(0.18560, 0.66081), control2: pt(0.33064, 0.79484))
        p.closeSubpath()
        return p
    }
}

struct OwlOutlineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.49329, 0.18561))
        p.addCurve(to: pt(0.81058, 0.47858), control1: pt(0.66528, 0.18200), control2: pt(0.80711, 0.31340))
        p.addCurve(to: pt(0.50587, 0.78463), control1: pt(0.81405, 0.64377), control2: pt(0.67786, 0.78101))
        p.addCurve(to: pt(0.18858, 0.49165), control1: pt(0.33389, 0.78824), control2: pt(0.19205, 0.65684))
        p.addCurve(to: pt(0.49329, 0.18561), control1: pt(0.18511, 0.32646), control2: pt(0.32130, 0.18922))
        p.closeSubpath()
        return p
    }
}

struct OwlBeakShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.44219, 0.48894))
        p.addLine(to: pt(0.49755, 0.37596))
        p.addLine(to: pt(0.55761, 0.48651))
        p.addLine(to: pt(0.51854, 0.56623))
        p.addCurve(to: pt(0.48457, 0.56695), control1: pt(0.51171, 0.58018), control2: pt(0.49198, 0.58059))
        p.addLine(to: pt(0.44219, 0.48894))
        p.closeSubpath()
        return p
    }
}

struct OwlFeetLeftShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.41921, 0.77021))
        p.addCurve(to: pt(0.39926, 0.75108), control1: pt(0.41898, 0.75942), control2: pt(0.41005, 0.75085))
        p.addCurve(to: pt(0.38012, 0.77103), control1: pt(0.38846, 0.75130), control2: pt(0.37990, 0.76024))
        p.addLine(to: pt(0.38082, 0.80401))
        p.addCurve(to: pt(0.40077, 0.82315), control1: pt(0.38104, 0.81481), control2: pt(0.38998, 0.82337))
        p.addCurve(to: pt(0.41990, 0.80319), control1: pt(0.41156, 0.82292), control2: pt(0.42013, 0.81399))
        p.addLine(to: pt(0.41921, 0.77021))
        p.closeSubpath()
        p.move(to: pt(0.45830, 0.76939))
        p.addCurve(to: pt(0.43835, 0.75026), control1: pt(0.45807, 0.75860), control2: pt(0.44914, 0.75003))
        p.addCurve(to: pt(0.41921, 0.77021), control1: pt(0.42755, 0.75048), control2: pt(0.41898, 0.75942))
        p.addLine(to: pt(0.41990, 0.80319))
        p.addCurve(to: pt(0.43986, 0.82233), control1: pt(0.42013, 0.81399), control2: pt(0.42906, 0.82255))
        p.addCurve(to: pt(0.45899, 0.80237), control1: pt(0.45065, 0.82210), control2: pt(0.45922, 0.81317))
        p.addLine(to: pt(0.45830, 0.76939))
        p.closeSubpath()
        p.move(to: pt(0.49739, 0.76857))
        p.addCurve(to: pt(0.47743, 0.74944), control1: pt(0.49716, 0.75778), control2: pt(0.48823, 0.74921))
        p.addCurve(to: pt(0.45830, 0.76939), control1: pt(0.46664, 0.74966), control2: pt(0.45807, 0.75860))
        p.addLine(to: pt(0.45899, 0.80237))
        p.addCurve(to: pt(0.47895, 0.82151), control1: pt(0.45922, 0.81317), control2: pt(0.46815, 0.82173))
        p.addCurve(to: pt(0.49808, 0.80155), control1: pt(0.48974, 0.82128), control2: pt(0.49831, 0.81234))
        p.addLine(to: pt(0.49739, 0.76857))
        p.closeSubpath()
        return p
    }
}

struct OwlFeetRightShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.55276, 0.76741))
        p.addCurve(to: pt(0.53281, 0.74827), control1: pt(0.55254, 0.75661), control2: pt(0.54360, 0.74804))
        p.addCurve(to: pt(0.51368, 0.76823), control1: pt(0.52202, 0.74850), control2: pt(0.51345, 0.75743))
        p.addLine(to: pt(0.51437, 0.80121))
        p.addCurve(to: pt(0.53432, 0.82034), control1: pt(0.51460, 0.81200), control2: pt(0.52353, 0.82057))
        p.addCurve(to: pt(0.55346, 0.80039), control1: pt(0.54512, 0.82012), control2: pt(0.55368, 0.81118))
        p.addLine(to: pt(0.55276, 0.76741))
        p.closeSubpath()
        p.move(to: pt(0.59185, 0.76659))
        p.addCurve(to: pt(0.57190, 0.74745), control1: pt(0.59163, 0.75579), control2: pt(0.58269, 0.74722))
        p.addCurve(to: pt(0.55276, 0.76741), control1: pt(0.56110, 0.74768), control2: pt(0.55254, 0.75661))
        p.addLine(to: pt(0.55346, 0.80039))
        p.addCurve(to: pt(0.57341, 0.81952), control1: pt(0.55368, 0.81118), control2: pt(0.56262, 0.81975))
        p.addCurve(to: pt(0.59254, 0.79957), control1: pt(0.58421, 0.81929), control2: pt(0.59277, 0.81036))
        p.addLine(to: pt(0.59185, 0.76659))
        p.closeSubpath()
        p.move(to: pt(0.63094, 0.76576))
        p.addCurve(to: pt(0.61099, 0.74663), control1: pt(0.63072, 0.75497), control2: pt(0.62178, 0.74640))
        p.addCurve(to: pt(0.59185, 0.76659), control1: pt(0.60019, 0.74686), control2: pt(0.59163, 0.75579))
        p.addLine(to: pt(0.59255, 0.79957))
        p.addCurve(to: pt(0.61250, 0.81870), control1: pt(0.59277, 0.81036), control2: pt(0.60171, 0.81893))
        p.addCurve(to: pt(0.63163, 0.79875), control1: pt(0.62329, 0.81847), control2: pt(0.63186, 0.80954))
        p.addLine(to: pt(0.63094, 0.76576))
        p.closeSubpath()
        return p
    }
}

struct OwlCrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.49232, 0.43620))
        p.addLine(to: pt(0.66285, 0.21893))
        p.addLine(to: pt(0.54138, 0.19379))
        p.addLine(to: pt(0.50228, 0.18573))
        p.addLine(to: pt(0.46388, 0.18653))
        p.addLine(to: pt(0.31661, 0.22620))
        p.addLine(to: pt(0.33383, 0.25565))
        p.addLine(to: pt(0.39028, 0.30694))
        p.addLine(to: pt(0.45459, 0.33720))
        p.addLine(to: pt(0.49232, 0.43620))
        p.closeSubpath()
        return p
    }
}

struct OwlGoggleLeftShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.09866, 0.22290))
        p.addLine(to: pt(0.32114, 0.21822))
        p.addCurve(to: pt(0.50297, 0.39257), control1: pt(0.41949, 0.21616), control2: pt(0.50090, 0.29421))
        p.addCurve(to: pt(0.32862, 0.57440), control1: pt(0.50503, 0.49092), control2: pt(0.42698, 0.57233))
        p.addLine(to: pt(0.28423, 0.57533))
        p.addCurve(to: pt(0.10240, 0.40098), control1: pt(0.18588, 0.57739), control2: pt(0.10447, 0.49934))
        p.addLine(to: pt(0.10053, 0.31194))
        p.addLine(to: pt(0.09960, 0.26742))
        p.addLine(to: pt(0.09866, 0.22290))
        p.closeSubpath()
        return p
    }
}

struct OwlGoggleRimLeftShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.32139, 0.23017))
        p.addCurve(to: pt(0.49102, 0.39282), control1: pt(0.41315, 0.22824), control2: pt(0.48909, 0.30106))
        p.addCurve(to: pt(0.32837, 0.56245), control1: pt(0.49295, 0.48457), control2: pt(0.42013, 0.56052))
        p.addLine(to: pt(0.28398, 0.56338))
        p.addCurve(to: pt(0.11435, 0.40073), control1: pt(0.19223, 0.56531), control2: pt(0.11628, 0.49249))
        p.addLine(to: pt(0.11086, 0.23459))
        p.addLine(to: pt(0.32139, 0.23017))
        p.closeSubpath()
        return p
    }
}

struct OwlDiscLeftShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.35739, 0.54829))
        p.addCurve(to: pt(0.48274, 0.39305), control1: pt(0.42839, 0.54680), control2: pt(0.48451, 0.47730))
        p.addCurve(to: pt(0.35098, 0.24321), control1: pt(0.48097, 0.30881), control2: pt(0.42198, 0.24172))
        p.addCurve(to: pt(0.22563, 0.39845), control1: pt(0.27998, 0.24470), control2: pt(0.22386, 0.31421))
        p.addCurve(to: pt(0.35739, 0.54829), control1: pt(0.22740, 0.48270), control2: pt(0.28639, 0.54979))
        p.closeSubpath()
        return p
    }
}

struct OwlGoggleRightShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.88935, 0.20629))
        p.addLine(to: pt(0.66687, 0.21096))
        p.addCurve(to: pt(0.49252, 0.39279), control1: pt(0.56851, 0.21303), control2: pt(0.49046, 0.29443))
        p.addCurve(to: pt(0.67435, 0.56713), control1: pt(0.49459, 0.49114), control2: pt(0.57600, 0.56920))
        p.addLine(to: pt(0.71874, 0.56620))
        p.addCurve(to: pt(0.89309, 0.38437), control1: pt(0.81710, 0.56413), control2: pt(0.89515, 0.48273))
        p.addLine(to: pt(0.89121, 0.29533))
        p.addLine(to: pt(0.89028, 0.25081))
        p.addLine(to: pt(0.88935, 0.20629))
        p.closeSubpath()
        return p
    }
}

struct OwlGoggleRimRightShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.66712, 0.22291))
        p.addCurve(to: pt(0.50447, 0.39254), control1: pt(0.57536, 0.22484), control2: pt(0.50254, 0.30078))
        p.addCurve(to: pt(0.67410, 0.55518), control1: pt(0.50640, 0.48429), control2: pt(0.58234, 0.55711))
        p.addLine(to: pt(0.71849, 0.55425))
        p.addCurve(to: pt(0.88114, 0.38462), control1: pt(0.81025, 0.55233), control2: pt(0.88307, 0.47638))
        p.addLine(to: pt(0.87765, 0.21849))
        p.addLine(to: pt(0.66712, 0.22291))
        p.closeSubpath()
        return p
    }
}

struct OwlDiscRightShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.64285, 0.53129))
        p.addCurve(to: pt(0.51132, 0.39216), control1: pt(0.57185, 0.53278), control2: pt(0.51296, 0.47049))
        p.addCurve(to: pt(0.63690, 0.24763), control1: pt(0.50967, 0.31383), control2: pt(0.56590, 0.24912))
        p.addCurve(to: pt(0.76843, 0.38676), control1: pt(0.70789, 0.24614), control2: pt(0.76678, 0.30843))
        p.addCurve(to: pt(0.64285, 0.53129), control1: pt(0.77007, 0.46509), control2: pt(0.71385, 0.52979))
        p.closeSubpath()
        return p
    }
}

struct OwlBellyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.45072, 0.62304))
        p.addCurve(to: pt(0.45417, 0.62660), control1: pt(0.45273, 0.62299), control2: pt(0.45443, 0.62460))
        p.addCurve(to: pt(0.44629, 0.64158), control1: pt(0.45342, 0.63238), control2: pt(0.45062, 0.63769))
        p.addCurve(to: pt(0.43054, 0.64780), control1: pt(0.44195, 0.64547), control2: pt(0.43637, 0.64768))
        p.addCurve(to: pt(0.41455, 0.64225), control1: pt(0.42472, 0.64792), control2: pt(0.41904, 0.64595))
        p.addCurve(to: pt(0.40604, 0.62761), control1: pt(0.41005, 0.63854), control2: pt(0.40703, 0.63335))
        p.addCurve(to: pt(0.40934, 0.62390), control1: pt(0.40570, 0.62562), control2: pt(0.40732, 0.62395))
        p.addCurve(to: pt(0.41346, 0.62744), control1: pt(0.41136, 0.62386), control2: pt(0.41299, 0.62548))
        p.addCurve(to: pt(0.41780, 0.63534), control1: pt(0.41417, 0.63042), control2: pt(0.41567, 0.63315))
        p.addCurve(to: pt(0.42557, 0.63992), control1: pt(0.41994, 0.63754), control2: pt(0.42262, 0.63912))
        p.addCurve(to: pt(0.43459, 0.63989), control1: pt(0.42853, 0.64072), control2: pt(0.43164, 0.64071))
        p.addCurve(to: pt(0.44233, 0.63526), control1: pt(0.43754, 0.63907), control2: pt(0.44021, 0.63747))
        p.addCurve(to: pt(0.44675, 0.62674), control1: pt(0.44459, 0.63291), control2: pt(0.44613, 0.62995))
        p.addCurve(to: pt(0.45072, 0.62304), control1: pt(0.44714, 0.62476), control2: pt(0.44870, 0.62308))
        p.closeSubpath()
        p.move(to: pt(0.52315, 0.62151))
        p.addCurve(to: pt(0.52660, 0.62508), control1: pt(0.52516, 0.62147), control2: pt(0.52686, 0.62308))
        p.addCurve(to: pt(0.51872, 0.64007), control1: pt(0.52585, 0.63086), control2: pt(0.52306, 0.63618))
        p.addCurve(to: pt(0.50297, 0.64629), control1: pt(0.51438, 0.64396), control2: pt(0.50879, 0.64617))
        p.addCurve(to: pt(0.48697, 0.64074), control1: pt(0.49714, 0.64641), control2: pt(0.49147, 0.64444))
        p.addCurve(to: pt(0.47847, 0.62609), control1: pt(0.48248, 0.63703), control2: pt(0.47946, 0.63183))
        p.addCurve(to: pt(0.48177, 0.62238), control1: pt(0.47812, 0.62410), control2: pt(0.47975, 0.62243))
        p.addCurve(to: pt(0.48589, 0.62592), control1: pt(0.48378, 0.62234), control2: pt(0.48542, 0.62396))
        p.addCurve(to: pt(0.49205, 0.63543), control1: pt(0.48679, 0.62970), control2: pt(0.48897, 0.63306))
        p.addCurve(to: pt(0.50282, 0.63898), control1: pt(0.49513, 0.63781), control2: pt(0.49893, 0.63906))
        p.addCurve(to: pt(0.51342, 0.63499), control1: pt(0.50670, 0.63890), control2: pt(0.51045, 0.63749))
        p.addCurve(to: pt(0.51918, 0.62522), control1: pt(0.51640, 0.63248), control2: pt(0.51843, 0.62904))
        p.addCurve(to: pt(0.52315, 0.62151), control1: pt(0.51957, 0.62324), control2: pt(0.52113, 0.62155))
        p.closeSubpath()
        p.move(to: pt(0.59557, 0.61999))
        p.addCurve(to: pt(0.59903, 0.62356), control1: pt(0.59759, 0.61995), control2: pt(0.59929, 0.62156))
        p.addCurve(to: pt(0.59381, 0.63575), control1: pt(0.59845, 0.62803), control2: pt(0.59664, 0.63225))
        p.addCurve(to: pt(0.58297, 0.64339), control1: pt(0.59097, 0.63925), control2: pt(0.58722, 0.64189))
        p.addCurve(to: pt(0.56974, 0.64423), control1: pt(0.57873, 0.64489), control2: pt(0.57414, 0.64518))
        p.addCurve(to: pt(0.55803, 0.63800), control1: pt(0.56534, 0.64327), control2: pt(0.56128, 0.64112))
        p.addCurve(to: pt(0.55089, 0.62457), control1: pt(0.55428, 0.63440), control2: pt(0.55178, 0.62969))
        p.addCurve(to: pt(0.55420, 0.62086), control1: pt(0.55055, 0.62258), control2: pt(0.55218, 0.62090))
        p.addCurve(to: pt(0.55831, 0.62440), control1: pt(0.55621, 0.62082), control2: pt(0.55784, 0.62244))
        p.addCurve(to: pt(0.56266, 0.63230), control1: pt(0.55903, 0.62737), control2: pt(0.56053, 0.63010))
        p.addCurve(to: pt(0.57043, 0.63687), control1: pt(0.56479, 0.63449), control2: pt(0.56748, 0.63607))
        p.addCurve(to: pt(0.57945, 0.63684), control1: pt(0.57338, 0.63767), control2: pt(0.57650, 0.63766))
        p.addCurve(to: pt(0.58718, 0.63222), control1: pt(0.58239, 0.63603), control2: pt(0.58507, 0.63443))
        p.addCurve(to: pt(0.59161, 0.62370), control1: pt(0.58944, 0.62986), control2: pt(0.59098, 0.62690))
        p.addCurve(to: pt(0.59557, 0.61999), control1: pt(0.59200, 0.62172), control2: pt(0.59356, 0.62003))
        p.closeSubpath()
        p.move(to: pt(0.48788, 0.66739))
        p.addCurve(to: pt(0.49133, 0.67096), control1: pt(0.48990, 0.66735), control2: pt(0.49160, 0.66896))
        p.addCurve(to: pt(0.48345, 0.68594), control1: pt(0.49058, 0.67673), control2: pt(0.48779, 0.68205))
        p.addCurve(to: pt(0.46770, 0.69216), control1: pt(0.47911, 0.68983), control2: pt(0.47353, 0.69204))
        p.addCurve(to: pt(0.45171, 0.68661), control1: pt(0.46188, 0.69228), control2: pt(0.45620, 0.69031))
        p.addCurve(to: pt(0.44320, 0.67197), control1: pt(0.44721, 0.68290), control2: pt(0.44419, 0.67771))
        p.addCurve(to: pt(0.44650, 0.66826), control1: pt(0.44286, 0.66998), control2: pt(0.44449, 0.66830))
        p.addCurve(to: pt(0.45062, 0.67180), control1: pt(0.44852, 0.66822), control2: pt(0.45015, 0.66984))
        p.addCurve(to: pt(0.45678, 0.68132), control1: pt(0.45153, 0.67558), control2: pt(0.45370, 0.67894))
        p.addCurve(to: pt(0.46755, 0.68486), control1: pt(0.45986, 0.68370), control2: pt(0.46366, 0.68495))
        p.addCurve(to: pt(0.47816, 0.68087), control1: pt(0.47144, 0.68478), control2: pt(0.47518, 0.68337))
        p.addCurve(to: pt(0.48392, 0.67110), control1: pt(0.48114, 0.67836), control2: pt(0.48317, 0.67492))
        p.addCurve(to: pt(0.48788, 0.66739), control1: pt(0.48430, 0.66912), control2: pt(0.48586, 0.66743))
        p.closeSubpath()
        p.move(to: pt(0.56031, 0.66587))
        p.addCurve(to: pt(0.56376, 0.66944), control1: pt(0.56232, 0.66583), control2: pt(0.56402, 0.66744))
        p.addCurve(to: pt(0.55854, 0.68163), control1: pt(0.56318, 0.67390), control2: pt(0.56138, 0.67812))
        p.addCurve(to: pt(0.54771, 0.68927), control1: pt(0.55571, 0.68513), control2: pt(0.55196, 0.68777))
        p.addCurve(to: pt(0.53448, 0.69010), control1: pt(0.54346, 0.69077), control2: pt(0.53888, 0.69105))
        p.addCurve(to: pt(0.52277, 0.68388), control1: pt(0.53007, 0.68915), control2: pt(0.52602, 0.68700))
        p.addCurve(to: pt(0.51563, 0.67045), control1: pt(0.51902, 0.68028), control2: pt(0.51651, 0.67557))
        p.addCurve(to: pt(0.51893, 0.66674), control1: pt(0.51528, 0.66846), control2: pt(0.51691, 0.66678))
        p.addCurve(to: pt(0.52305, 0.67028), control1: pt(0.52095, 0.66670), control2: pt(0.52258, 0.66832))
        p.addCurve(to: pt(0.52782, 0.67861), control1: pt(0.52381, 0.67345), control2: pt(0.52547, 0.67634))
        p.addCurve(to: pt(0.53575, 0.68290), control1: pt(0.53003, 0.68072), control2: pt(0.53277, 0.68221))
        p.addCurve(to: pt(0.54476, 0.68255), control1: pt(0.53873, 0.68359), control2: pt(0.54184, 0.68347))
        p.addCurve(to: pt(0.55233, 0.67765), control1: pt(0.54768, 0.68163), control2: pt(0.55029, 0.67993))
        p.addCurve(to: pt(0.55634, 0.66958), control1: pt(0.55437, 0.67537), control2: pt(0.55575, 0.67258))
        p.addCurve(to: pt(0.56031, 0.66587), control1: pt(0.55673, 0.66760), control2: pt(0.55829, 0.66591))
        p.closeSubpath()
        return p
    }
}

struct OwlMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.49283, 0.55264))
        p.addCurve(to: pt(0.50869, 0.55230), control1: pt(0.49610, 0.55932), control2: pt(0.50570, 0.55912))
        p.addLine(to: pt(0.52295, 0.51984))
        p.addCurve(to: pt(0.51476, 0.50758), control1: pt(0.52552, 0.51399), control2: pt(0.52115, 0.50745))
        p.addLine(to: pt(0.48489, 0.50821))
        p.addCurve(to: pt(0.47722, 0.52080), control1: pt(0.47850, 0.50834), control2: pt(0.47440, 0.51506))
        p.addLine(to: pt(0.49283, 0.55264))
        p.closeSubpath()
        return p
    }
}
