//
//  DetailSearchView.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 4/01/12.
//

import SwiftUI
import ComposableArchitecture

struct DetailSearchView: View {
    private let store: Store<DetailSearchState, DetailSearchAction>
    @ObservedObject private var viewStore: ViewStore<DetailSearchState, DetailSearchAction>
    private let keyword: String
    private let user: User
    @Binding private var setting: Setting
    private let blurRadius: Double
    private let tagTranslator: TagTranslator

    init(
        store: Store<DetailSearchState, DetailSearchAction>,
        keyword: String, user: User, setting: Binding<Setting>, blurRadius: Double, tagTranslator: TagTranslator
    ) {
        self.store = store
        viewStore = ViewStore(store)
        self.keyword = keyword
        self.user = user
        _setting = setting
        self.blurRadius = blurRadius
        self.tagTranslator = tagTranslator
    }

    var body: some View {
        GenericList(
            galleries: viewStore.galleries,
            setting: setting,
            pageNumber: viewStore.pageNumber,
            loadingState: viewStore.loadingState,
            footerLoadingState: viewStore.footerLoadingState,
            fetchAction: { viewStore.send(.fetchGalleries()) },
            fetchMoreAction: { viewStore.send(.fetchMoreGalleries) },
            navigateAction: { viewStore.send(.setNavigation(.detail($0))) },
            translateAction: {
                tagTranslator.lookup(word: $0, returnOriginal: !setting.translatesTags)
            }
        )
        .sheet(
            unwrapping: viewStore.binding(\.$route),
            case: /DetailSearchState.Route.detail,
            isEnabled: DeviceUtil.isPad
        ) { route in
            NavigationView {
                DetailView(
                    store: store.scope(state: \.detailState, action: DetailSearchAction.detail),
                    gid: route.wrappedValue, user: user, setting: $setting,
                    blurRadius: blurRadius, tagTranslator: tagTranslator
                )
            }
            .autoBlur(radius: blurRadius).environment(\.inSheet, true).navigationViewStyle(.stack)
        }
        .sheet(unwrapping: viewStore.binding(\.$route), case: /DetailSearchState.Route.quickSearch) { _ in
            QuickSearchView(
                store: store.scope(state: \.quickDetailSearchState, action: DetailSearchAction.quickSearch)
            ) { keyword in
                viewStore.send(.setNavigation(nil))
                viewStore.send(.fetchGalleries(keyword))
            }
            .accentColor(setting.accentColor)
            .autoBlur(radius: blurRadius)
        }
        .sheet(unwrapping: viewStore.binding(\.$route), case: /DetailSearchState.Route.filters) { _ in
            FiltersView(store: store.scope(state: \.filtersState, action: DetailSearchAction.filters))
                .accentColor(setting.accentColor).autoBlur(radius: blurRadius)
        }
        .searchable(text: viewStore.binding(\.$keyword)) {
            TagSuggestionView(
                keyword: viewStore.binding(\.$keyword), translations: tagTranslator.translations,
                showsImages: setting.showsImagesInTags, isEnabled: setting.showsTagsSearchSuggestion
            )
        }
        .onSubmit(of: .search) {
            viewStore.send(.fetchGalleries())
        }
        .onAppear {
            if viewStore.galleries.isEmpty {
                DispatchQueue.main.async {
                    viewStore.send(.fetchGalleries(keyword))
                }
            }
        }
        .background(navigationLink)
        .toolbar(content: toolbar)
        .navigationTitle(viewStore.lastKeyword)
    }

    @ViewBuilder private var navigationLink: some View {
        if DeviceUtil.isPhone {
            NavigationLink(unwrapping: viewStore.binding(\.$route), case: /DetailSearchState.Route.detail) { route in
                DetailView(
                    store: store.scope(state: \.detailState, action: DetailSearchAction.detail),
                    gid: route.wrappedValue, user: user, setting: $setting,
                    blurRadius: blurRadius, tagTranslator: tagTranslator
                )
            }
        }
    }
    private func toolbar() -> some ToolbarContent {
        CustomToolbarItem {
            ToolbarFeaturesMenu {
                FiltersButton {
                    viewStore.send(.setNavigation(.filters))
                }
                QuickSearchButton {
                    viewStore.send(.setNavigation(.quickSearch))
                }
            }
        }
    }
}

struct DetailSearchView_Previews: PreviewProvider {
    static var previews: some View {
        DetailSearchView(
            store: .init(
                initialState: .init(),
                reducer: detailSearchReducer,
                environment: DetailSearchEnvironment(
                    urlClient: .live,
                    fileClient: .live,
                    imageClient: .live,
                    deviceClient: .live,
                    hapticClient: .live,
                    cookiesClient: .live,
                    databaseClient: .live,
                    clipboardClient: .live,
                    appDelegateClient: .live,
                    uiApplicationClient: .live
                )
            ),
            keyword: .init(),
            user: .init(),
            setting: .constant(.init()),
            blurRadius: 0,
            tagTranslator: .init()
        )
    }
}
