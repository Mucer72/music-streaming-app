//
//  SectionView.swift
//  PersonalMusicHost
//
//  Generic section container with a title and arbitrary content.
//  Used across Dashboard to wrap scrollable content rows.
//

import SwiftUI

struct SectionView<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .bold()
                .padding(.horizontal)
            content
        }
    }
}
