//
//  ContentView.swift
//  MeeptoMeepMS
//
//  Created by Panagiotis on 2024-11-06.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connectionService: ConnectionService
    @State private var messageText = ""
    
    var body: some View {
        VStack {
            // Connection status bar
            Text(connectionService.connectionStatus)
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    connectionService.connectionStatus.contains("Connected") ? Color.green.opacity(0.2) :
                    connectionService.connectionStatus.contains("Connecting") ? Color.yellow.opacity(0.2) :
                    Color.red.opacity(0.2)
                )
            
            List(Array(connectionService.receivedMessages.enumerated()), id: \.offset) { index, message in
                let (messageText, deviceName, isFromMe) = message
                VStack(alignment: isFromMe ? .trailing : .leading) {
                    Text(deviceName)
                        .font(.caption)
                        .foregroundColor(.gray)
                    HStack {
                        if isFromMe {
                            Spacer()
                        }
                        Text(messageText)
                            .padding(10)
                            .background(isFromMe ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: isFromMe ? .trailing : .leading)
                        if !isFromMe {
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            
            HStack {
                TextField("Message", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .frame(minHeight: 44)
                
                Button(action: {
                    guard !messageText.isEmpty else { return }
                    connectionService.send(message: messageText)
                    messageText = ""
                }) {
                    Text("Send")
                        .padding(.horizontal)
                        .frame(minHeight: 44)
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
