import Foundation
import Testing
@testable import GravitySDK

extension SDKSingletonTests {
    struct SharedSanitizerContractTests {
        @Test(arguments: [
            ("V1", "https://public.test/,https://user:SECRET@private.test/path?token=x", "https://public.test/,https://private.test/path"),
            ("V2", "https://user:SE/CRET@host/p", "https://[redacted]"),
            ("V3", "https://user:SE?CRET@host/p", "https://[redacted]"),
            ("V4", "https://user:SE#CRET@host/p", "https://[redacted]"),
            ("V5", "wss://user:SECRET@socket.test/x", "wss://socket.test/x"),
            ("V6", "https://proxy.test/redirect/ftp://user:SECRET@private.test/x", "https://proxy.test/redirect/ftp://private.test/x"),
            ("V7", "//user:SECRET@host/p", "//host/p"),
            ("V8", "POST https://api.test/v1/choose?email=a@b.com failed for user@example.com", "POST https://api.test/v1/choose failed for user@example.com"),
            ("V9", "https://host.test/users/@alice/profile", "https://host.test/users/@alice/profile"),
            ("V10", "#0 main (file:///Users/me/app/lib/main.dart:10:5)", "#0 main (file:///Users/me/app/lib/main.dart:10:5)"),
            ("V11", "Illegal character in authority at index 8: https://user:SE CRET@host/p", "Illegal character in authority at index 8: https://[redacted]host/p"),
            ("V12", "https://u:pa ss@h", "https://[redacted]h"),
            ("V13", #"https:\/\/user:SECRET@host\/p"#, "https://host/p"),
            ("V14", "https%3A%2F%2Fuser%3ASECRET%40host", "https://host"),
            ("V15", "HTTPS://User:SECRET@Host.test/P?q=1#f", "HTTPS://Host.test/P"),
            ("V16", "https://host:8443/users/@alice/profile", "https://[redacted]"),
            ("V17", "https://public.test:443/p?email=user@X", "https://[redacted]"),
            ("V18", "https://user:123/456@host/p", "https://[redacted]"),
            ("V19", "https://[::1]:8443/users/@alice/profile?x=1", "https://[::1]:8443/users/@alice/profile"),
            ("V20", "https://host:8443/plain/path?token=x", "https://host:8443/plain/path"),
            ("V21", "content:https://user:SECRET@host/p", "content:https://host/p"),
            ("V22", "redis://user:SECRET@host:6379/0", "redis://host:6379/0"),
            ("V23", "POST https://api.test:8443 failed for user@example.com", "POST https://api.test:8443 failed for user@example.com"),
            ("V24", "connect https://api.test:8443: timeout; admin@corp.test notified", "connect https://api.test:8443: timeout; admin@corp.test notified"),
            ("V25", "url:https://user:SECRET@host.test/p?token=x", "url:https://host.test/p"),
            ("V26", "REQUEST:https://user:SECRET@host.test/p", "REQUEST:https://host.test/p"),
            ("V27", "failed:reason:https://user:SECRET@host.test/p tail", "failed:reason:https://host.test/p tail"),
            ("V28", "jdbc:postgresql://user:SECRET@host.test/db", "jdbc:postgresql://host.test/db"),
            ("V29", "blob:https://user:SECRET@host.test/x", "blob:https://host.test/x"),
            ("V30", "https://user:SECRET@host.test/p", "https://host.test/p"),
            ("V31", #"https:\\/\\/user:SECRET@host\\/p"#, "https://host/p"),
            ("V32", "https:%2F%2Fuser:SECRET@host.test/p", "https://host.test/p"),
            ("V33", "https://user:SECRET/path", "https://[redacted]"),
            ("V34", "https://api.test:", "https://api.test:"),
            ("V35", "https://[user:123]/SECRET@host/p", "https://[redacted]"),
            ("V36", "retry-2.https://user:SECRET@host/p", "retry-2.https://host/p"),
            ("V37", "Authorization: Bearer ABC123", "Authorization: [redacted]"),
            ("V38a", "authorization: [Bearer SECRET]", "authorization: [redacted]"),
            ("V38b", "Authorization: Token SECRET", "Authorization: [redacted]"),
            ("V38c", "Proxy-Authorization: Bearer SECRET", "Proxy-Authorization: [redacted]"),
            ("V38d", "x-authorization: SECRET", "x-authorization: [redacted]"),
            ("V38e", "Authorization: Bearer SECRET\nnext line", "Authorization: [redacted]\nnext line")
        ])
        func sharedVectors(vector: (String, String, String)) {
            let (name, input, expected) = vector
            let clean = ReportSanitizer.sanitizeUrls(input)
            #expect(clean == expected, "\(name): endpoint and surrounding text must survive")
            #expect(!clean.contains("SECRET"))
            if ["V2", "V3", "V4", "V11"].contains(name) {
                #expect(!clean.contains("SE"))
                #expect(!clean.contains("CRET"))
            }
            if name == "V12" {
                #expect(!clean.contains("pa"))
                #expect(!clean.contains("ss@"))
            }
        }

        @Test func authorizationInFreeTextIsCaseInsensitiveAndPreservesFollowingLines() {
            for value in ["Authorization: Bearer ABC123", "authorization=bearer ABC123", "AUTHORIZATION: bEaReR ABC123"] {
                let clean = ReportSanitizer.sanitizeText(value + "\nnext line https://host/p?SECRET", limit: 1000)
                #expect(!clean.contains("ABC123"))
                #expect(!clean.lowercased().contains("bearer"))
                #expect(clean.contains("\nnext line https://host/p"))
            }
            let report = LogMessage(message: "Authorization: Bearer ABC123", level: .error,
                sec: "s", uid: "d", ses: "s", sdkVersion: "1", platform: "iOS",
                stacktrace: "authorization=bearer ABC123", extra: ["header": "Authorization: Bearer ABC123"],
                tags: ["header": "Authorization: Bearer ABC123"])
            #expect(report.message == "Authorization: [redacted]")
            #expect(!report.stacktrace.contains("ABC123"))
            #expect(!report.extra["header"]!.contains("ABC123"))
            #expect(!report.tags["header"]!.contains("ABC123"))
        }

        @Test func authorizationRedactsCompleteLineAcrossReportFields() {
            for name in ["Authorization", "authorization", "Proxy-Authorization", "X-AUTHORIZATION"] {
                for separator in [":", "="] {
                    for newline in ["\n", "\r\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"] {
                        let input = name + separator + " [Token SECRET] extra SECRET" + newline + "next https://host/p?SECRET"
                        let expected = name + ": [redacted]" + newline + "next https://host/p"
                        let report = LogMessage(message: input, level: .error,
                            sec: "s", uid: "d", ses: "s", sdkVersion: "1", platform: "iOS",
                            stacktrace: input, extra: ["header": input], tags: ["header": input])
                        #expect(report.message == expected)
                        #expect(report.stacktrace == expected)
                        #expect(report.extra["header"] == expected)
                        #expect(report.tags["header"] == expected)
                        #expect(!report.message.contains("SECRET"))
                        #expect(ReportSanitizer.sanitizeUrls(expected) == expected)
                    }
                }
            }
        }

        @Test func ipv6ExemptionRequiresValidAddressSyntax() {
            for address in ["::", "::1", "2001:db8::1", "2001:DB8:0:0:8:800:200C:417A",
                            "::ffff:192.0.2.128", "2001:db8:0:0:0:ffff:192.0.2.128",
                            "fe80::1%en0", "fe80::1%25en0", "fe80::1%nonexistent-zone._~9",
                            "fe80::1%25zone%20name", "fe80::1%25zone%3Aname", "fe80::1%25zone%E2%82%AC"] {
                let endpoint = "https://[\(address)]:8443/users/@alice/profile"
                #expect(ReportSanitizer.sanitizeUrls(endpoint + "?token=SECRET") == endpoint)
            }
            for address in ["user:123", "gggg::1", "1:2:3:4:5:6:7", "1:2:3:4:5:6:7:8:9",
                            "1::2::3", "12345::1", "::ffff:999.1.1.1", "fe80::1%", "fe80::1%25", "fe80::1%en:0", "fe80::1%25en%ZZ"] {
                let clean = ReportSanitizer.sanitizeUrls("https://[\(address)]/SECRET@host/p")
                #expect(clean == "https://[redacted]")
                #expect(!clean.contains("SECRET"))
            }
        }

        @Test func invalidBracketedAuthorityCannotReachEncodedTransportReport() throws {
            let raw = "https://[user:123]/SECRET@host/p"
            let url = URL(string: raw)?.absoluteString ?? raw
            let failure = NetworkError.transportFailure(URLError(.cannotFindHost), method: "GET", url: url)
            let report = LogMessage(message: String(describing: failure), level: .error,
                sec: "s", uid: "uid", ses: "ses", sdkVersion: "1", platform: "iOS")
            let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
            #expect(report.message == "GET https://[redacted] -> URLError(-1003)")
            for secret in ["SECRET", "123", "user:"] { #expect(!json.contains(secret)) }
        }

        @Test func finalRulingJsonSlashFormsRemoveCredentials() {
            for value in [#"https:\u002f\u002Fuser:SECRET@host.test\u002fp"#,
                          #"https:\/\/user:SECRET@host.test\/p"#,
                          #"https:\\/\\/user:SECRET@host.test\\/p"#,
                          "https:%2f%2Fuser:SECRET@host.test/p"] {
                let clean = ReportSanitizer.sanitizeUrls(value)
                #expect(clean == "https://host.test/p")
                #expect(!clean.contains("SECRET"))
            }
        }

        @Test func genericSchemesAndOpaquePrefixesStripOnlyUrlSecrets() {
            for scheme in ["redis", "mongodb", "amqp", "x+custom.1"] {
                #expect(ReportSanitizer.sanitizeUrls(scheme + "://u:SECRET@host/p?SECRET") == scheme + "://host/p")
                #expect(ReportSanitizer.sanitizeUrls(scheme + "%3A%2F%2Fu%3ASECRET%40host/p") == scheme + "://host/p")
                #expect(ReportSanitizer.sanitizeUrls(scheme + #":\/\/u:SECRET@host\/p"#) == scheme + "://host/p")
            }
            #expect(ReportSanitizer.sanitizeUrls("https://proxy.test/path/content:https://user:SECRET@host/p")
                == "https://proxy.test/path/content:https://host/p")
            #expect(ReportSanitizer.sanitizeUrls("https://proxy.test/path/content:https://u:SE CRET@host/p")
                == "https://proxy.test/path/content:https://[redacted]host/p")
            #expect(ReportSanitizer.sanitizeUrls("https://proxy.test:443/path/content:https://user:SECRET@host/p")
                == "https://[redacted]")
            #expect(ReportSanitizer.sanitizeUrls("jar:file:///a/b.jar!/p?SECRET") == "jar:file:///a/b.jar!/p")
            #expect(ReportSanitizer.sanitizeUrls("content:https://u:SE CRET@host/p after") == "content:https://[redacted]host/p after")
        }

        @Test func otherNetworkSchemesStripQueriesWithoutCredentials() {
            #expect(ReportSanitizer.sanitizeUrls("ftp://host/p?SECRET wss://host/p#SECRET ws://host:88/p?q=SECRET")
                == "ftp://host/p wss://host/p ws://host:88/p")
        }

        @Test func nonNetworkSchemesKeepTheirPathsAndDropQueryAndFragment() {
            for scheme in ["file", "package", "dart", "content", "data", "myapp", "mailto"] {
                let endpoint = scheme + ":/path/to/source:10:5"
                #expect(ReportSanitizer.sanitizeUrls(endpoint + "?SECRET#SECRET after") == endpoint + " after")
            }
        }

        @Test func malformedUserinfoDoesNotDropFollowingText() {
            #expect(ReportSanitizer.sanitizeUrls("before https://u:pa ss@h/p next https://public.test/p after")
                == "before https://[redacted]h/p next https://public.test/p after")
            #expect(ReportSanitizer.sanitizeUrls("before https://u:pa\"ss@h/p next")
                == "before https://[redacted]h/p next")
        }

        @Test func numericPasswordsCannotMasqueradeAsPorts() {
            for input in ["https://user:123/SECRET@host/p", "//user:12/SECRET@host/p",
                          "https://user:123?SECRET@host/p", "https://user:123/456@host/p",
                          "https://public.test:443/p?email=user@X", "https://file:123/SECRET@host/p", "https://user:http://SECRET@host/p"] {
                let clean = ReportSanitizer.sanitizeUrls(input)
                #expect(clean == (input.hasPrefix("//") ? "//[redacted]" : "https://[redacted]"))
                for secret in ["SECRET", "user:", "123", "456"] { #expect(!clean.contains(secret)) }
            }
            #expect(ReportSanitizer.sanitizeUrls("https://u:12 SECRET@h/p") == "https://[redacted]h/p")
        }

        @Test func legitimateEndpointsAndFollowingTextAreNotDropped() {
            for input in ["Failed https://api.test: timeout after 5s",
                          "connect http://127.0.0.1:8080, retrying soon",
                          "GET https://api.test/path// -> 500",
                          "https://host.test/a//b:c/d tail", "note // a:b then more text"] {
                #expect(ReportSanitizer.sanitizeUrls(input) == input)
            }
            #expect(ReportSanitizer.sanitizeUrls("myapp://open/x?token=SECRET") == "myapp://open/x")
        }

        @Test func lengthBoundDropsOnlyCrossedTokenAndKeepsFollowingText() {
            let input = "before https://user:" + String(repeating: "SECRET", count: 2000) + "@host/p after https://public.test/p?token=SECRET done"
            #expect(ReportSanitizer.sanitizeText(input, limit: 1000) == "before  after https://public.test/p done")
        }

        @Test func whitespaceCredentialsKeepPortsAndNestedEndpointContext() {
            for scheme in ["http", "https", "ws", "wss", "ftp"] {
                for host in ["host", "host:8443", "[::1]:8443"] {
                    for prefix in ["", "https://proxy.test/redirect/"] {
                        let input = prefix + scheme + "://u:SE CRET@" + host + "/p?SECRET"
                        let clean = ReportSanitizer.sanitizeUrls(input)
                        #expect(clean == prefix + scheme + "://[redacted]" + host + "/p")
                        #expect(!clean.contains("SE"))
                        #expect(!clean.contains("CRET"))
                    }
                }
            }
        }

        @Test func nestedRelativeCredentialsAreNotMistakenForPathData() {
            #expect(ReportSanitizer.sanitizeUrls("https://proxy.test/path//user:SECRET@private.test/p?token=x")
                == "https://proxy.test/path//private.test/p")
            #expect(ReportSanitizer.sanitizeUrls("https://proxy.test/path//user:12/SECRET@private.test/p")
                == "https://proxy.test/path//[redacted]")
            #expect(ReportSanitizer.sanitizeUrls("https://host/a//b:c/d tail") == "https://host/a//b:c/d tail")
        }

        @Test func finalLengthLimitCannotLeavePartialAuthority() {
            let input = "before https://" + String(repeating: "a", count: 2000) + ".test/path after"
            let clean = ReportSanitizer.sanitizeText(input, limit: 1000)
            #expect(clean == "before  after...")
            #expect(!clean.contains("https://"))
        }

        @Test func largeEncodedInputCompletesWithinGenerousBudget() {
            let input = String(repeating: "%3a%2f%2f ", count: 100_000)
            let started = ProcessInfo.processInfo.systemUptime
            let result = ReportSanitizer.sanitizeText(input, limit: 5000)
            let duration = ProcessInfo.processInfo.systemUptime - started
            #expect(duration < 20, "million-character encoded input took \(duration) seconds")
            #expect(result.count <= 5000)
            // The generic scheme regexp must not retry a long unsuccessful
            // scheme candidate from every character in that same run.
            let letters = String(repeating: "a", count: 1_000_000)
            let lettersStarted = ProcessInfo.processInfo.systemUptime
            let unchanged = ReportSanitizer.sanitizeUrls(letters) == letters
            #expect(unchanged)
            #expect(ProcessInfo.processInfo.systemUptime - lettersStarted < 20)
        }

        @Test func encodedChainsKeepEveryEndpointAndUnrelatedEscapes() {
            let chain = String(repeating: "https%3a%2f%2fuser%3aSECRET%40host/p ", count: 30_000)
            let clean = ReportSanitizer.sanitizeUrls(chain)
            #expect(clean == String(repeating: "https://host/p ", count: 30_000))
            #expect(!clean.contains("SECRET"))
            #expect(ReportSanitizer.sanitizeUrls(#"plain \/ text"#) == #"plain \/ text"#)
            #expect(ReportSanitizer.sanitizeUrls("https://u:pa\u{00A0}ss@h/p after") == "https://[redacted]h/p after")
        }

        @Test func legitimatePortAndPathAtSignKeepEndpoint() {
            #expect(ReportSanitizer.sanitizeUrls("https://host:8443/users/@alice/profile?q=SECRET")
                == "https://[redacted]")
            #expect(ReportSanitizer.sanitizeUrls("https://[::1]:8443/users/@alice/profile?q=SECRET")
                == "https://[::1]:8443/users/@alice/profile")
        }
    }
}
