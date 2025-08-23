//
//  ContentViewModel.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import Foundation
import Combine

@MainActor
class ContentViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var emails: [Email] = []
    @Published var importantEmails: [Email] = []
    @Published var promotionalEmails: [Email] = []
    @Published var calendarEmails: [Email] = []
    @Published var searchResults: [Email] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let gmailService: GmailServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(gmailService: GmailServiceProtocol = GmailService.shared) {
        self.gmailService = gmailService
        setupSearchSubscription()
        loadInitialData()
    }
    
    private func setupSearchSubscription() {
        $searchText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] searchText in
                Task {
                    await self?.performSearchInternal(query: searchText)
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadInitialData() {
        Task {
            await loadEmails()
            await loadCategoryEmails()
        }
    }
    
    func loadEmails() async {
        isLoading = true
        errorMessage = nil
        
        do {
            emails = try await gmailService.fetchTodaysUnreadEmails()
        } catch {
            errorMessage = "Failed to load emails: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func loadCategoryEmails() async {
        do {
            async let important = gmailService.fetchImportantEmails()
            async let promotional = gmailService.fetchPromotionalEmails()
            async let calendar = gmailService.fetchCalendarEmails()
            
            importantEmails = try await important
            promotionalEmails = try await promotional
            calendarEmails = try await calendar
        } catch {
            errorMessage = "Failed to load category emails: \(error.localizedDescription)"
        }
    }
    
    func performSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        do {
            searchResults = try await gmailService.searchEmails(query: query)
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
    }
    
    private func performSearchInternal(query: String) async {
        await performSearch(query: query)
    }
    
    func markEmailAsRead(_ emailId: String) {
        Task {
            do {
                try await gmailService.markAsRead(emailId: emailId)
                // Update local state by reloading data
                // Note: Email struct would need to be mutable for direct updates
                await loadEmails()
            } catch {
                errorMessage = "Failed to mark email as read: \(error.localizedDescription)"
            }
        }
    }
    
    func markEmailAsImportant(_ emailId: String) {
        Task {
            do {
                try await gmailService.markAsImportant(emailId: emailId)
                await loadEmails()
                await loadCategoryEmails()
            } catch {
                errorMessage = "Failed to mark email as important: \(error.localizedDescription)"
            }
        }
    }
    
    func refresh() async {
        await loadEmails()
        await loadCategoryEmails()
    }
}