import Foundation

/// 大学ごとの初期設定値（湘南工科大学）。
///
/// - URL はすべて「設定」画面から上書きできます（UserDefaults に保存）。
/// - 「推定」と書いた Campus Square のページは、他大学の Campus Square で一般的な画面IDからの推定です。
///   違っていた場合は、アプリ内ブラウザで正しいページを開き「このページを〜に設定」で置き換えてください。
/// - ここには公開情報だけを書きます。ID・パスワードは書かないでください（設定画面から入力→キーチェーン保存）。
enum DefaultConfig {
    static let university = UniversityConfig(
        universityName: "湘南工科大学",
        // 自動ログイン・アプリ内ブラウザで「大学のサイト」とみなすドメイン
        trustedDomain: "shonan-it.ac.jp",

        moodleBaseURL: "https://moodle2026.shonan-it.ac.jp",
        // 公開ログインページで確認したフォーム（2026-11-23 時点）
        moodleLogin: LoginSpec(
            username: "#username",
            password: "#password",
            submit: "#loginbtn",
            error: "#loginerrormessage"
        ),

        campusSquare: CampusSquareURLs(
            login: "https://portal.shonan-it.ac.jp/campusweb/",
            portal: "https://portal.shonan-it.ac.jp/campusweb/portal.do?page=main",
            timetable: "https://portal.shonan-it.ac.jp/campusweb/campussquare.do?_flowId=RSW0001000-flow",     // 推定: 履修登録・登録状況照会
            cancellations: "https://portal.shonan-it.ac.jp/campusweb/campussquare.do?_flowId=KHW0001100-flow", // 休講補講参照（2026-11-24 確認）
            grades: "https://portal.shonan-it.ac.jp/campusweb/campussquare.do?_flowId=SIW0001300-flow",        // 推定: 成績照会
            syllabus: "https://portal.shonan-it.ac.jp/campusweb/campussquare.do?_flowId=SYW0001000-flow",      // 推定: シラバス
            attendance: "https://syusseki.shonan-it.ac.jp/campusaa/"                                            // ログインページ上のリンクより
        ),
        // 公開ログインページで確認したフォーム（2026-11-23 時点）
        campusLogin: LoginSpec(
            username: "#userNameInput",
            password: "#passwordInput",
            submit: "#login-form button[type=submit]",
            error: nil
        ),

        // 大学メール: shonan-it.ac.jp / sit.shonan-it.ac.jp の MX が Google を指している（2026-11-23 DNSで確認）
        mail: MailConfig(
            webURL: "https://mail.google.com/",
            provider: .googleWorkspace
        )
    )
}
