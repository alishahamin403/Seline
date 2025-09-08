//
//  SelineUser.swift
//  Seline
//
//  Created by Claude Code on 2025-09-08.
//

import Foundation

struct SelineUser: Codable {
    let id: String // Google ID
    var supabaseId: UUID?
    let email: String
    let name: String
    let profileImageURL: String?
    let accessToken: String
    let refreshToken: String?
    let tokenExpirationDate: Date?
    
    var isTokenExpired: Bool {
        guard let expirationDate = tokenExpirationDate else { return true }
        return Date() >= expirationDate
    }
}