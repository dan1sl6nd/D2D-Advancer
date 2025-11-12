import SwiftUI
import FirebaseAuth

enum AppError: LocalizedError {
    case dataError(String)
    case networkError(String)
    case authenticationError(String)
    case permissionError(String)
    case validationError(String)
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .dataError(let message):
            return "Data Error: \(message)"
        case .networkError(let message):
            return "Network Error: \(message)"
        case .authenticationError(let message):
            return "Authentication Error: \(message)"
        case .permissionError(let message):
            return "Permission Error: \(message)"
        case .validationError(let message):
            return "Validation Error: \(message)"
        case .unknownError(let message):
            return "Error: \(message)"
        }
    }
    
    var userFriendlyMessage: String {
        switch self {
        case .dataError:
            return "Unable to save or load data. Please try again."
        case .networkError:
            return "Network connection issue. Please check your internet connection and try again."
        case .authenticationError:
            return "Authentication failed. Please sign in again."
        case .permissionError:
            return "Permission denied. Please check your account settings."
        case .validationError(let message):
            return message
        case .unknownError:
            return "Something went wrong. Please try again."
        }
    }
    
    var shouldRetry: Bool {
        switch self {
        case .networkError, .dataError, .unknownError:
            return true
        case .authenticationError, .permissionError, .validationError:
            return false
        }
    }
}

class ErrorHandler: ObservableObject {
    @Published var currentError: AppError?
    @Published var showingError = false
    
    static let shared = ErrorHandler()
    
    private init() {}
    
    func handle(_ error: Error, context: String = "") {
        let appError = categorizeError(error, context: context)
        
        print("🚨 [\(context)] \(appError.errorDescription ?? "Unknown error")")
        
        DispatchQueue.main.async {
            self.currentError = appError
            self.showingError = true
        }
    }
    
    func handleFirebaseError(_ error: Error, context: String = "") {
        let appError: AppError
        
        if let authError = error as? AuthErrorCode {
            switch authError.code {
            case .networkError:
                appError = .networkError("Network connection failed")
            case .userNotFound, .wrongPassword, .invalidEmail:
                appError = .authenticationError("Invalid credentials")
            case .emailAlreadyInUse:
                appError = .validationError("Email address is already in use")
            case .weakPassword:
                appError = .validationError("Password is too weak")
            case .tooManyRequests:
                appError = .networkError("Too many requests. Please try again later")
            default:
                appError = .authenticationError("Authentication failed")
            }
        } else {
            appError = categorizeError(error, context: context)
        }
        
        handle(appError, context: context)
    }
    
    private func categorizeError(_ error: Error, context: String) -> AppError {
        let errorMessage = error.localizedDescription.lowercased()
        
        if errorMessage.contains("network") || errorMessage.contains("internet") || errorMessage.contains("connection") {
            return .networkError(error.localizedDescription)
        } else if errorMessage.contains("permission") || errorMessage.contains("authorization") || errorMessage.contains("firestore") {
            return .permissionError(error.localizedDescription)
        } else if errorMessage.contains("core data") || errorMessage.contains("save") || errorMessage.contains("fetch") {
            return .dataError(error.localizedDescription)
        } else if errorMessage.contains("auth") || errorMessage.contains("sign") {
            return .authenticationError(error.localizedDescription)
        } else {
            return .unknownError(error.localizedDescription)
        }
    }
    
    private func handle(_ appError: AppError, context: String) {
        print("🚨 [\(context)] \(appError.errorDescription ?? "Unknown error")")
        
        DispatchQueue.main.async {
            self.currentError = appError
            self.showingError = true
        }
    }
    
    func clearError() {
        currentError = nil
        showingError = false
    }
}

struct ErrorAlert: ViewModifier {
    @ObservedObject var errorHandler = ErrorHandler.shared
    let onRetry: (() -> Void)?
    
    init(onRetry: (() -> Void)? = nil) {
        self.onRetry = onRetry
    }
    
    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: $errorHandler.showingError) {
                if let error = errorHandler.currentError, error.shouldRetry, let retry = onRetry {
                    Button("Retry") {
                        errorHandler.clearError()
                        retry()
                    }
                }
                Button("OK") {
                    errorHandler.clearError()
                }
            } message: {
                if let error = errorHandler.currentError {
                    Text(error.userFriendlyMessage)
                }
            }
    }
}

extension View {
    func errorAlert(onRetry: (() -> Void)? = nil) -> some View {
        modifier(ErrorAlert(onRetry: onRetry))
    }
}

struct RetryableOperation {
    let maxRetries: Int
    let retryDelay: TimeInterval
    
    init(maxRetries: Int = 3, retryDelay: TimeInterval = 1.0) {
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }
    
    func execute<T>(
        operation: @escaping () async throws -> T,
        onError: ((Error, Int) -> Void)? = nil
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                onError?(error, attempt + 1)
                
                // Check if this is an AppError and if we should retry
                if let appError = error as? AppError, !appError.shouldRetry {
                    print("🚫 Error should not be retried: \(appError.errorDescription ?? "Unknown")")
                    throw error
                }
                
                // Only wait if we're going to attempt again
                if attempt < maxRetries - 1 {
                    try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? AppError.unknownError("Operation failed after \(maxRetries) attempts")
    }
}