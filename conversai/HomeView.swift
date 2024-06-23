import SwiftUI
import LocalAuthentication

struct HomeView: View {
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String? = nil
    @State private var isAuthenticated = false
    @State private var isAuthenticating = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    if isAuthenticated {
                        ContentView()
                    } else {
                        logo
                        authenticationForm
                        if isAuthenticating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                .scaleEffect(1.5)
                        }
                        biometricButton
                    }
                }
                .padding(.top)
                .navigationBarHidden(true)
                .alert(isPresented: Binding<Bool>.constant($errorMessage.wrappedValue != nil), content: {
                    Alert(title: Text("Error"), message: Text($errorMessage.wrappedValue ?? "Unknown error"), dismissButton: .default(Text("OK")) {
                        self.errorMessage = nil
                    })
                })
            }
        }
    }
    
    
    var logo: some View {
        Text("speaktree ai")
            .font(.largeTitle)
            .bold()
            .padding(.bottom, 40)
    }
    
    var authenticationForm: some View {
        VStack(spacing: 20) {
            TextField("Email", text: $email)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .disableAutocorrection(true)
                .autocapitalization(.none)
                .keyboardType(.emailAddress)
            
            SecureField("Password", text: $password)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
            
            Button(action: {
                loginUser(email: email, password: password)
            }) {
                Text("Login")
                    .bold()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]), startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(10)
                    .shadow(radius: 10)
            }
            .padding(.top, 20)
            
            Button(action: {
                createUser(email: email, password: password)
            }) {
                Text("Sign Up")
                    .bold()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(LinearGradient(gradient: Gradient(colors: [Color.green, Color.blue]), startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(10)
                    .shadow(radius: 10)
            }
        }
        .padding(.horizontal)
    }
    
    private func loginUser(email: String, password: String) {
        isAuthenticating = true
        DispatchQueue.global().async {
            // Simulate a network delay
            sleep(1)
            DispatchQueue.main.async {
                self.isAuthenticating = false
                if let storedPassword = UserDefaults.standard.string(forKey: email), storedPassword == password {
                    KeychainManager.saveCredentials(email: email, password: password)
                    self.isAuthenticated = true
                } else {
                    self.errorMessage = "Invalid email or password"
                }
            }
        }
    }

    private func createUser(email: String, password: String) {
        isAuthenticating = true
        DispatchQueue.global().async {
            // Simulate a network delay
            sleep(1)
            DispatchQueue.main.async {
                self.isAuthenticating = false
                UserDefaults.standard.set(password, forKey: email)
                // Save credentials on successful account creation
                KeychainManager.saveCredentials(email: email, password: password)
                self.isAuthenticated = true
            }
        }
    }
    
    var biometricButton: some View {
        Button(action: authenticateUserBiometrically) {
            Image(systemName: "faceid")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                .foregroundColor(.blue)
        }
        .padding(.top, 20)
    }

    private func authenticateUserBiometrically() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Identify yourself!"

            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) {
                success, authenticationError in

                DispatchQueue.main.async {
                    if success {
                        self.retrieveCredentialsAndLogin()
                    } else {
                        self.errorMessage = "Failed to authenticate"
                    }
                }
            }
        } else {
            self.errorMessage = "No biometric authentication available"
        }
    }

    private func retrieveCredentialsAndLogin() {
        if let credentials = KeychainManager.retrieveCredentials() {
            self.email = credentials.email
            self.password = credentials.password
            // Use the retrieved credentials to login
            loginUser(email: self.email, password: self.password)
        } else {
            self.errorMessage = "Could not retrieve credentials"
        }
    }
}

class KeychainManager {

    static func saveCredentials(email: String, password: String) {
        let emailData = email.data(using: .utf8)!
        let passwordData = password.data(using: .utf8)!

        let queryEmail: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                         kSecAttrAccount as String: "userEmail",
                                         kSecValueData as String: emailData]

        let queryPassword: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                            kSecAttrAccount as String: "userPassword",
                                            kSecValueData as String: passwordData]

        // Delete old item before adding new item
        SecItemDelete(queryEmail as CFDictionary)
        SecItemDelete(queryPassword as CFDictionary)

        // Add new item
        let statusEmail = SecItemAdd(queryEmail as CFDictionary, nil)
        let statusPassword = SecItemAdd(queryPassword as CFDictionary, nil)

        if statusEmail == errSecSuccess && statusPassword == errSecSuccess {
            print("Credentials saved successfully.")
        } else {
            print("Failed to save credentials.")
        }
    }

    static func retrieveCredentials() -> (email: String, password: String)? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: "userEmail",
                                    kSecReturnData as String: kCFBooleanTrue!,
                                    kSecMatchLimit as String: kSecMatchLimitOne]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let emailData = item as? Data, let email = String(data: emailData, encoding: .utf8) else {
            print("Failed to retrieve email.")
            return nil
        }

        let queryPassword: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                            kSecAttrAccount as String: "userPassword",
                                            kSecReturnData as String: kCFBooleanTrue!,
                                            kSecMatchLimit as String: kSecMatchLimitOne]

        var itemPassword: CFTypeRef?
        let statusPassword = SecItemCopyMatching(queryPassword as CFDictionary, &itemPassword)

        guard statusPassword == errSecSuccess, let passwordData = itemPassword as? Data, let password = String(data: passwordData, encoding: .utf8) else {
            print("Failed to retrieve password.")
            return nil
        }

        return (email, password)
    }
}
