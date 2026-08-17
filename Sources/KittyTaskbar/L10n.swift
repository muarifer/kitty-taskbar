import Foundation

/// Küçük yerelleştirme yardımcısı: varsayılan İngilizce, sistem dili Türkçe ise Türkçe.
/// (Elle oluşturulan .app paketinde .lproj kaynakları taşımamak için bilinçli olarak koddan.)
enum L10n {
    nonisolated(unsafe) static var isTurkish: Bool =
        Locale.preferredLanguages.first?.hasPrefix("tr") ?? false

    static func t(_ english: String, _ turkish: String) -> String {
        isTurkish ? turkish : english
    }

    static var kittyNotRunning: String { t("kitty is not running", "Kitty çalışmıyor") }
    static var kittenMissing: String { t("kitten command not found — is kitty installed?", "kitten komutu bulunamadı — kitty kurulu mu?") }
    static var connectionFailed: String {
        t("Could not connect to kitty. Is this set in kitty.conf?\nallow_remote_control yes\nlisten_on unix:/tmp/kitty-{kitty_pid}",
          "Kitty'ye bağlanılamadı. kitty.conf içinde şunlar ayarlı mı?\nallow_remote_control yes\nlisten_on unix:/tmp/kitty-{kitty_pid}")
    }
    static var openKitty: String { t("Open kitty", "Kitty'yi Aç") }
    static var quit: String { t("Quit", "Çıkış") }
    static var dropZone: String { t("Drop here to detach into a new window", "Yeni pencereye ayırmak için buraya bırak") }
    static var untitled: String { t("(untitled)", "(başlıksız)") }

    static func window(_ n: Int) -> String { t("Window \(n)", "Pencere \(n)") }
    static func instanceWindow(_ i: Int, _ w: Int) -> String {
        t("kitty \(i) · Window \(w)", "Kitty \(i) · Pencere \(w)")
    }

    static var errorKittenMissing: String { t("kitten command not found", "kitten komutu bulunamadı") }
    static func errorLaunchFailed(_ reason: String) -> String {
        t("could not launch kitten: \(reason)", "kitten başlatılamadı: \(reason)")
    }
    static var errorTimeout: String { t("kitty did not respond (timeout)", "kitty yanıt vermedi (zaman aşımı)") }
    static func errorCommandFailed(_ code: Int) -> String {
        t("kitty command failed (exit code \(code))", "kitty komutu başarısız oldu (kod \(code))")
    }
}
