import SwiftUI
import MessageUI

struct HelpAndSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var issueDescription = ""
    @State private var result: Result<MFMailComposeResult, Error>? = nil
    @State private var isShowingMailView = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Describe your issue")) {
                    TextEditor(text: $issueDescription)
                        .frame(height: 200)
                }

                Button(action: {
                    if MFMailComposeViewController.canSendMail() {
                        self.isShowingMailView.toggle()
                    } else {
                        print("Can't send email")
                    }
                }) {
                    Text("Send")
                }
            }
            .navigationTitle("Help & Support")
            .navigationBarItems(trailing: Button("Dismiss") {
                dismiss()
            })
            .sheet(isPresented: $isShowingMailView) {
                MailView(result: self.$result, recipients: ["alishah.amin96@gmail.com"], subject: "Seline App Support Request", messageBody: issueDescription)
            }
        }
    }
}

struct MailView: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentation
    @Binding var result: Result<MFMailComposeResult, Error>?
    var recipients: [String]
    var subject: String
    var messageBody: String

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        @Binding var presentation: PresentationMode
        @Binding var result: Result<MFMailComposeResult, Error>?

        init(presentation: Binding<PresentationMode>,
             result: Binding<Result<MFMailComposeResult, Error>?>) {
            _presentation = presentation
            _result = result
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            defer {
                $presentation.wrappedValue.dismiss()
            }
            if let error = error {
                self.result = .failure(error)
                return
            }
            self.result = .success(result)
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(presentation: presentation, result: $result)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<MailView>) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(recipients)
        vc.setSubject(subject)
        vc.setMessageBody(messageBody, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: UIViewControllerRepresentableContext<MailView>) {
    }
}
