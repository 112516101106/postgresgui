//
//  ConnectionStatusBanner.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

enum ConnectionTestStatus: Equatable {
    case idle
    case testing
    case testingSSH
    case success
    case error(message: String)
}

struct ConnectionStatusBanner: View {
    let status: ConnectionTestStatus
    let onDismiss: () -> Void
    
    var body: some View {
        Group {
            switch status {
            case .idle:
                EmptyView()
            case .testing:
                testingBanner(message: "Testing connection...")
            case .testingSSH:
                testingBanner(message: "Establishing SSH tunnel...")
            case .success:
                successBanner()
            case .error(let message):
                errorBanner(message: message)
            }
        }
    }
    
    // MARK: - Testing State
    
    private func testingBanner(message: String) -> some View {
        HStack(spacing: 12) {
            SpinnerIcon()

            Text(message)
                .font(.system(size: 13))
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Dismiss connection status")
            .accessibilityLabel("Dismiss connection status")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .cornerRadius(6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Testing connection")
        .accessibilityAddTraits(.updatesFrequently)
    }
    
    // MARK: - Success State
    
    private func successBanner() -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(red: 0.13, green: 0.77, blue: 0.37)) // #22C55E
                .font(.system(size: 16))
            
            Text("Connection successful")
                .font(.system(size: 13))
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Dismiss connection status")
            .accessibilityLabel("Dismiss connection status")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(red: 0.13, green: 0.77, blue: 0.37), lineWidth: 1) // #22C55E
        )
        .cornerRadius(6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection successful")
    }
    
    // MARK: - Error State
    
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(red: 0.94, green: 0.27, blue: 0.27)) // #EF4444
                .font(.system(size: 16))
            
            Text(message)
                .font(.system(size: 13))
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Dismiss connection status")
            .accessibilityLabel("Dismiss connection status")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(red: 0.94, green: 0.27, blue: 0.27), lineWidth: 1) // #EF4444
        )
        .cornerRadius(6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection failed. \(message)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Spinner Icon

struct SpinnerIcon: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        Image(systemName: "circle.dashed")
            .font(.system(size: 16))
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

