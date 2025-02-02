//
//  CookiesClient.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 4/01/02.
//

import Foundation
import ComposableArchitecture

struct CookiesClient {
    let clearAll: () -> Effect<Never, Never>
    let getCookie: (URL, String) -> CookieValue
    private let removeCookie: (URL, String) -> Void
    private let checkExistence: (URL, String) -> Bool
    private let initializeCookie: (HTTPCookie, String) -> HTTPCookie
}

extension CookiesClient {
    static let live: Self = .init(
        clearAll: {
            .fireAndForget {
                if let historyCookies = HTTPCookieStorage.shared.cookies {
                    historyCookies.forEach {
                        HTTPCookieStorage.shared.deleteCookie($0)
                    }
                }
            }
        },
        getCookie: { url, key in
            var value = CookieValue(
                rawValue: "", localizedString: L10n.Localizable.Struct.CookieValue.LocalizedString.none
            )
            guard let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty else { return value }

            cookies.forEach { cookie in
                guard let expiresDate = cookie.expiresDate, cookie.name == key && !cookie.value.isEmpty else { return }
                guard expiresDate > .now else {
                    value = CookieValue(
                        rawValue: "", localizedString: L10n.Localizable.Struct.CookieValue.LocalizedString.expired
                    )
                    return
                }
                guard cookie.value != Defaults.Cookie.mystery else {
                    value = CookieValue(
                        rawValue: cookie.value, localizedString:
                            L10n.Localizable.Struct.CookieValue.LocalizedString.mystery
                    )
                    return
                }
                value = CookieValue(rawValue: cookie.value, localizedString: "")
            }

            return value
        },
        removeCookie: { url, key in
            if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
                cookies.forEach { cookie in
                    guard cookie.name == key else { return }
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                }
            }
        },
        checkExistence: { url, key in
            if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
                var existence: HTTPCookie?
                cookies.forEach { cookie in
                    guard cookie.name == key else { return }
                    existence = cookie
                }
                return existence != nil
            } else {
                return false
            }
        },
        initializeCookie: { cookie, value in
            var properties = cookie.properties
            properties?[.value] = value
            return HTTPCookie(properties: properties ?? [:]) ?? HTTPCookie()
        }
    )
}

// MARK: Foundation
extension CookiesClient {
    private func setCookie(
        for url: URL, key: String, value: String, path: String = "/",
        expiresTime: TimeInterval = .oneYear
    ) {
        let expiredDate = Date(timeIntervalSinceNow: expiresTime)
        let properties: [HTTPCookiePropertyKey: Any] = [
            .path: path, .name: key, .value: value,
            .originURL: url, .expires: expiredDate
        ]
        if let cookie = HTTPCookie(properties: properties) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }
    func editCookie(for url: URL, key: String, value: String) {
        var newCookie: HTTPCookie?
        if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            cookies.forEach { cookie in
                guard cookie.name == key else { return }
                newCookie = initializeCookie(cookie, value)
                removeCookie(url, key)
            }
        }
        guard let cookie = newCookie else { return }
        HTTPCookieStorage.shared.setCookie(cookie)
    }
    func setOrEditCookie(for url: URL, key: String, value: String) -> Effect<Never, Never> {
        .fireAndForget {
            if checkExistence(url, key) {
                editCookie(for: url, key: key, value: value)
            } else {
                setCookie(for: url, key: key, value: value)
            }
        }
    }
}

// MARK: Accessor
extension CookiesClient {
    var didLogin: Bool {
        CookiesUtil.didLogin
    }
    var apiuid: String {
        getCookie(Defaults.URL.host, Defaults.Cookie.ipbMemberId).rawValue
    }
    var isSameAccount: Bool {
        let ehUID = getCookie(Defaults.URL.ehentai, Defaults.Cookie.ipbMemberId).rawValue
        let exUID = getCookie(Defaults.URL.exhentai, Defaults.Cookie.ipbMemberId).rawValue
        if !ehUID.isEmpty && !exUID.isEmpty { return ehUID == exUID } else { return false }
    }
    var shouldFetchIgneous: Bool {
        let url = Defaults.URL.exhentai
        return !getCookie(url, Defaults.Cookie.ipbMemberId).rawValue.isEmpty
        && !getCookie(url, Defaults.Cookie.ipbPassHash).rawValue.isEmpty
        && getCookie(url, Defaults.Cookie.igneous).rawValue.isEmpty
    }
    func removeYay() -> Effect<Never, Never> {
        .fireAndForget {
            removeCookie(Defaults.URL.exhentai, Defaults.Cookie.yay)
        }
    }
    func ignoreOffensive() -> Effect<Never, Never> {
        .merge(
            setOrEditCookie(for: Defaults.URL.ehentai, key: Defaults.Cookie.ignoreOffensive, value: "1"),
            setOrEditCookie(for: Defaults.URL.exhentai, key: Defaults.Cookie.ignoreOffensive, value: "1")
        )
    }
    func fulfillAnotherHostField() -> Effect<Never, Never> {
        let ehURL = Defaults.URL.ehentai
        let exURL = Defaults.URL.exhentai
        let memberIdKey = Defaults.Cookie.ipbMemberId
        let passHashKey = Defaults.Cookie.ipbPassHash
        let ehMemberId = getCookie(ehURL, memberIdKey).rawValue
        let ehPassHash = getCookie(ehURL, passHashKey).rawValue
        let exMemberId = getCookie(exURL, memberIdKey).rawValue
        let exPassHash = getCookie(exURL, passHashKey).rawValue

        if !ehMemberId.isEmpty && !ehPassHash.isEmpty && (exMemberId.isEmpty || exPassHash.isEmpty) {
            return .merge(
                setOrEditCookie(for: exURL, key: memberIdKey, value: ehMemberId),
                setOrEditCookie(for: exURL, key: passHashKey, value: ehPassHash)
            )
        } else if !exMemberId.isEmpty && !exPassHash.isEmpty && (ehMemberId.isEmpty || ehPassHash.isEmpty) {
            return .merge(
                setOrEditCookie(for: ehURL, key: memberIdKey, value: exMemberId),
                setOrEditCookie(for: ehURL, key: passHashKey, value: exPassHash)
            )
        } else {
            return .none
        }
    }
    func loadCookiesState(host: GalleryHost) -> CookiesState {
        let igneousKey = Defaults.Cookie.igneous
        let memberIDKey = Defaults.Cookie.ipbMemberId
        let passHashKey = Defaults.Cookie.ipbPassHash
        let igneous = getCookie(host.url, igneousKey)
        let memberID = getCookie(host.url, memberIDKey)
        let passHash = getCookie(host.url, passHashKey)
        return .init(
            host: host,
            igneous: .init(key: igneousKey, value: igneous, editingText: igneous.rawValue),
            memberID: .init(key: memberIDKey, value: memberID, editingText: memberID.rawValue),
            passHash: .init(key: passHashKey, value: passHash, editingText: passHash.rawValue)
        )
    }
    func getCookiesDescription(host: GalleryHost) -> String {
        var dictionary = [String: String]()
        [Defaults.Cookie.igneous, Defaults.Cookie.ipbMemberId, Defaults.Cookie.ipbPassHash].forEach { key in
            let cookieValue = getCookie(host.url, key)
            if !cookieValue.rawValue.isEmpty {
                dictionary[key] = cookieValue.rawValue
            }
        }
        return dictionary.description
    }
}

// MARK: SetCookies
extension CookiesClient {
    func setCookies(state: CookiesState) -> Effect<Never, Never> {
        let effects: [Effect<Never, Never>] = state.allCases.map { subState in
            setOrEditCookie(for: state.host.url, key: subState.key, value: subState.editingText)
        }
        return effects.isEmpty ? .none : .merge(effects)
    }
    func setCredentials(response: HTTPURLResponse) -> Effect<Never, Never> {
        .fireAndForget {
            guard let setString = response.allHeaderFields["Set-Cookie"] as? String else { return }
            setString.components(separatedBy: ", ")
                .flatMap { $0.components(separatedBy: "; ") }.forEach { value in
                    [Defaults.URL.ehentai, Defaults.URL.exhentai].forEach { url in
                        [
                            Defaults.Cookie.ipbMemberId,
                            Defaults.Cookie.ipbPassHash,
                            Defaults.Cookie.igneous
                        ].forEach { key in
                            guard !(url == Defaults.URL.ehentai && key == Defaults.Cookie.igneous),
                                  let range = value.range(of: "\(key)=") else { return }
                            setCookie(for: url, key: key, value: String(value[range.upperBound...]))
                        }
                    }
                }
        }
    }
    func setSkipServer(response: HTTPURLResponse) -> Effect<Never, Never> {
        .fireAndForget {
            guard let setString = response.allHeaderFields["Set-Cookie"] as? String else { return }
            setString.components(separatedBy: ", ")
                .flatMap { $0.components(separatedBy: "; ") }
                .forEach { value in
                    let key = Defaults.Cookie.skipServer
                    if let range = value.range(of: "\(key)=") {
                        setCookie(
                            for: Defaults.URL.host, key: key,
                            value: String(value[range.upperBound...]), path: "/s/"
                        )
                    }
                }
        }
    }
}

// MARK: Test
#if DEBUG
import XCTestDynamicOverlay

extension CookiesClient {
    static let failing: Self = .init(
        clearAll: { .failing("\(Self.self).clearAll is unimplemented") },
        getCookie: {
            XCTFail("\(Self.self).getCookie(\($0), \($1)) is unimplemented")
            return .empty
        },
        removeCookie: {
            XCTFail("\(Self.self).removeCookie(\($0), \($1)) is unimplemented")
        },
        checkExistence: {
            XCTFail("\(Self.self).checkExistence(\($0), \($1)) is unimplemented")
            return false
        },
        initializeCookie: {
            XCTFail("\(Self.self).initializeCookie(\($0), \($1)) is unimplemented")
            return .init()
        }
    )
}
#endif
extension CookiesClient {
    static let noop: Self = .init(
        clearAll: { .none },
        getCookie: { _, _ in .empty },
        removeCookie: { _, _ in },
        checkExistence: { _, _ in false },
        initializeCookie: { _, _ in .init() }
    )
}
