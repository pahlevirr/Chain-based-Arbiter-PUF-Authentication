/* client.c - Embedded client using a custom binary protocol
 *
 * This code implements the following:
 *  - Connects to a server on PORT_USED.
 *  - Constructs an AUTH_REQUEST message containing:
 *      [ HID_len (1B) ][ HID_j ][ CHlen (2B) ][ x_p_len (1B) ][ x_p ]
 *  - Processes incoming AUTH_MSG messages from the server,
 *    performs dummy error correction and a simulated PUF function (ZXK),
 *    and sends AUTH_MSG responses:
 *      [ HID_len (1B) ][ HID_j ][ COM_prime_len (1B) ][ COM_prime ][ Z_len (1B) ][ Z ]
 *  - Finally, it receives an AUTH_DONE message and checks the final MTL.
 *
 * Note: Several helper functions (e.g. getCRP, error_correction) are
 * simplified stubs.
 */

 #include <stdio.h>
 #include <stdlib.h>
 #include <stdint.h>
 #include <string.h>
 #include <stdarg.h>
 #include <unistd.h>
 #include <arpa/inet.h>
 #include <sys/socket.h>
 #include <time.h>
 #include <openssl/sha.h>
 
 #define PORT_USED      45555
 #define AUTH_REQUEST   0x06
 #define AUTH_MSG       0x07
 #define AUTH_ACK       0x08
 #define AUTH_DONE      0x09
 #define PRIME_USED     2147483647UL  // Use a large prime for security
 
 // --- Helper: Recv exactly n bytes ---
 ssize_t recvall(int sockfd, void *buf, size_t n) {
     size_t total = 0;
     ssize_t bytes;
     char *p = buf;
     while (total < n) {
         bytes = recv(sockfd, p + total, n - total, 0);
         if (bytes <= 0)
             return bytes;
         total += bytes;
     }
     return total;
 }
 
 // --- Helper: Send message with custom binary header ---
 // Header: [version (1B)][msgType (1B)][payload length (2B)]
 int send_message(int sockfd, uint8_t msgType, const uint8_t *payload, uint16_t payload_len) {
     uint8_t header[4];
     header[0] = 1;  // version
     header[1] = msgType;
     uint16_t net_len = htons(payload_len);
     memcpy(&header[2], &net_len, 2);
     if (send(sockfd, header, 4, 0) != 4)
         return -1;
     if (send(sockfd, payload, payload_len, 0) != payload_len)
         return -1;
     return 0;
 }
 
 // --- Helper: Receive message (header + payload) ---
 int recv_message(int sockfd, uint8_t *msgType, uint8_t **payload, uint16_t *payload_len) {
     uint8_t header[4];
     if (recvall(sockfd, header, 4) != 4)
         return -1;
     // header[0] is version (ignored)
     *msgType = header[1];
     memcpy(payload_len, &header[2], 2);
     *payload_len = ntohs(*payload_len);
     *payload = malloc(*payload_len);
     if (!*payload)
         return -1;
     if (recvall(sockfd, *payload, *payload_len) != *payload_len) {
         free(*payload);
         return -1;
     }
     return 0;
 }
 
 // --- Helper: Variadic hash_value ---
 // Concatenates count strings and returns the SHA256 hex digest.
 // The returned string must be freed by the caller.
 char* hash_value(int count, ...) {
     va_list args;
     int total_len = 0;
     va_start(args, count);
     for (int i = 0; i < count; i++) {
         char *s = va_arg(args, char*);
         total_len += strlen(s);
     }
     va_end(args);
     char *concat = malloc(total_len + 1);
     if (!concat) return NULL;
     concat[0] = '\0';
     va_start(args, count);
     for (int i = 0; i < count; i++) {
         char *s = va_arg(args, char*);
         strcat(concat, s);
     }
     va_end(args);
     
     unsigned char hash[SHA256_DIGEST_LENGTH];
     SHA256((unsigned char*)concat, strlen(concat), hash);
     free(concat);
     
     char *hash_str = malloc(65);
     if (!hash_str) return NULL;
     for (int i = 0; i < SHA256_DIGEST_LENGTH; i++)
         sprintf(hash_str + (i * 2), "%02x", hash[i]);
     hash_str[64] = '\0';
     return hash_str;
 }
 
 // --- Simulated PUF Function (ZXK) ---
 // Given M and R, returns Z as a string and sets *x to a random value.
 char* ZXK(const char *M, const char *R, int *x) {
     char *hash_R = hash_value(1, R);
     // Convert hash_R (hex string) to unsigned long
     unsigned long R_hashed = strtoul(hash_R, NULL, 16) % PRIME_USED;
     free(hash_R);
     *x = (rand() % 9000) + 1000;  // random integer between 1000 and 9999
     unsigned long M_val = strtoul(M, NULL, 16);
     unsigned long multiplier = (M_val * R_hashed) % PRIME_USED;
     unsigned long Z_val = (multiplier * (*x)) % PRIME_USED;
     
     char *Z_str = malloc(16);
     if (!Z_str) return NULL;
     snprintf(Z_str, 16, "%lu", Z_val);
     return Z_str;
 }
 
 // --- Simple error correction ---
 // This is a very simple scheme (for proof-of-concept only).
 // It assumes response is a string of '0' and '1' characters.
 char* error_correction(const char *response, const char *error_code) {
     size_t resp_len = strlen(response);
     char *corrected = strdup(response);
     if (!corrected) return NULL;
     size_t ec_len = strlen(error_code);
     for (size_t i = 0; i < ec_len; i += 2) {
         char parity[3] = { error_code[i], error_code[i+1], '\0' };
         size_t index = (i / 2) * 4;
         if (index + 3 < resp_len) {
             int sum = 0;
             for (size_t j = 0; j < 4; j++) {
                 sum += corrected[index + j] - '0';
             }
             int mod_val = sum % 4;
             char mod_str[3];
             sprintf(mod_str, "%02d", mod_val);
             if (strcmp(mod_str, parity) != 0) {
                 // Flip the first bit of this 4-bit chunk
                 corrected[index] = (corrected[index] == '0') ? '1' : '0';
             }
         }
     }
     return corrected;
 }
 
 // --- Stub for getCRP ---
 // In a real system, this would interface with an FPGA or similar.
 // Here we just return a dummy response string.
 const char* getCRP() {
     return "1010101010101010101010101010101010101010"; // dummy binary response
 }
 
 // --- Pack AUTH_REQUEST payload ---
 // Format: [ HID_len (1B) ][ HID_j ][ CHlen (2B) ][ x_p_len (1B) ][ x_p ]
 // Returns dynamically allocated buffer; length is set in *out_len.
 uint8_t* pack_auth_request(const char *HID_j, uint16_t CHlen, const char *x_p, uint16_t *out_len) {
     uint8_t hid_len = (uint8_t)strlen(HID_j);
     uint8_t x_p_len = (uint8_t)strlen(x_p);
     *out_len = 1 + hid_len + 2 + 1 + x_p_len;
     uint8_t *buffer = malloc(*out_len);
     if (!buffer) return NULL;
     int offset = 0;
     buffer[offset++] = hid_len;
     memcpy(buffer + offset, HID_j, hid_len);
     offset += hid_len;
     uint16_t net_CHlen = htons(CHlen);
     memcpy(buffer + offset, &net_CHlen, 2);
     offset += 2;
     buffer[offset++] = x_p_len;
     memcpy(buffer + offset, x_p, x_p_len);
     return buffer;
 }
 
 // --- Unpack AUTH_MSG payload received from server ---
 // Format: [ ACK_len (1B) ][ ACK ][ challenge_len (1B) ][ challenge ]
 //         [ error_code_len (1B) ][ error_code ][ OFFSET_len (1B) ][ OFFSET ]
 //         [ M_len (1B) ][ M ]
 typedef struct {
     char *ACK;
     char *challenge;
     char *error_code;
     char *OFFSET;
     char *M;
 } AuthMsgServer;
 
 int unpack_auth_msg_server(const uint8_t *payload, uint16_t payload_len, AuthMsgServer *msg) {
     int offset = 0;
     if (offset >= payload_len) return -1;
     uint8_t ack_len = payload[offset++];
     if (offset + ack_len > payload_len) return -1;
     msg->ACK = strndup((const char *)(payload + offset), ack_len);
     offset += ack_len;
 
     if (offset >= payload_len) return -1;
     uint8_t chall_len = payload[offset++];
     if (offset + chall_len > payload_len) return -1;
     msg->challenge = strndup((const char *)(payload + offset), chall_len);
     offset += chall_len;
 
     if (offset >= payload_len) return -1;
     uint8_t err_len = payload[offset++];
     if (offset + err_len > payload_len) return -1;
     msg->error_code = strndup((const char *)(payload + offset), err_len);
     offset += err_len;
 
     if (offset >= payload_len) return -1;
     uint8_t off_len = payload[offset++];
     if (offset + off_len > payload_len) return -1;
     msg->OFFSET = strndup((const char *)(payload + offset), off_len);
     offset += off_len;
 
     if (offset >= payload_len) return -1;
     uint8_t m_len = payload[offset++];
     if (offset + m_len > payload_len) return -1;
     msg->M = strndup((const char *)(payload + offset), m_len);
     offset += m_len;
     return 0;
 }
 
 // --- Pack AUTH_MSG response payload ---
 // Format: [ HID_len (1B) ][ HID_j ][ COM_prime_len (1B) ][ COM_prime ]
 //         [ Z_len (1B) ][ Z ]
 // Returns dynamically allocated buffer; length set in *out_len.
 uint8_t* pack_auth_msg_response(const char *HID_j, const char *COM_prime, const char *Z, uint16_t *out_len) {
     uint8_t hid_len = (uint8_t)strlen(HID_j);
     uint8_t com_len = (uint8_t)strlen(COM_prime);
     uint8_t z_len = (uint8_t)strlen(Z);
     *out_len = 1 + hid_len + 1 + com_len + 1 + z_len;
     uint8_t *buffer = malloc(*out_len);
     if (!buffer) return NULL;
     int offset = 0;
     buffer[offset++] = hid_len;
     memcpy(buffer + offset, HID_j, hid_len);
     offset += hid_len;
     buffer[offset++] = com_len;
     memcpy(buffer + offset, COM_prime, com_len);
     offset += com_len;
     buffer[offset++] = z_len;
     memcpy(buffer + offset, Z, z_len);
     return buffer;
 }
 
 // --- Unpack AUTH_DONE payload ---
 // Format: [ MTL_len (1B) ][ MTL ]
 char* unpack_auth_done(const uint8_t *payload, uint16_t payload_len) {
     if (payload_len < 1) return NULL;
     uint8_t mtl_len = payload[0];
     if (payload_len < 1 + mtl_len) return NULL;
     char *MTL = strndup((const char *)(payload + 1), mtl_len);
     return MTL;
 }
 
 // --- Helper: Convert integer to string ---
 char* int_to_str(int num) {
     char *buf = malloc(16);
     if (!buf) return NULL;
     snprintf(buf, 16, "%d", num);
     return buf;
 }
 
 // --- Main client (Prover) function ---
 void start_prover(const char *board) {
     srand(time(NULL));
 
     // Construct ID_j = "MD_" + board
     char ID_j[64];
     snprintf(ID_j, sizeof(ID_j), "MD_%s", board);
     
     // Compute HID_j = hash_value(1, ID_j)
     char *HID_j = hash_value(1, ID_j);
     
     uint16_t CHlen = 5;
     
     // Generate random x_p in [1000,9999] and convert to string
     int x_p_val = (rand() % 9000) + 1000;
     char x_p_str[16];
     snprintf(x_p_str, sizeof(x_p_str), "%d", x_p_val);
     
     // Compute x_pv = hash_value(2, x_p_str, ID_j)
     char *x_pv = hash_value(2, x_p_str, ID_j);
     
     // Create socket and connect
     int sockfd = socket(AF_INET, SOCK_STREAM, 0);
     if (sockfd < 0) {
         perror("Socket creation failed");
         exit(EXIT_FAILURE);
     }
     struct sockaddr_in serv_addr;
     serv_addr.sin_family = AF_INET;
     serv_addr.sin_port = htons(PORT_USED);
     serv_addr.sin_addr.s_addr = inet_addr("127.0.0.1"); // adjust to server IP as needed
     if (connect(sockfd, (struct sockaddr*)&serv_addr, sizeof(serv_addr)) < 0) {
         perror("Connect failed");
         close(sockfd);
         exit(EXIT_FAILURE);
     }
     
     // Pack and send AUTH_REQUEST
     uint16_t req_len;
     uint8_t *req_payload = pack_auth_request(HID_j, CHlen, x_p_str, &req_len);
     if (send_message(sockfd, AUTH_REQUEST, req_payload, req_len) < 0) {
         perror("Send AUTH_REQUEST failed");
         free(req_payload);
         close(sockfd);
         exit(EXIT_FAILURE);
     }
     free(req_payload);
     
     // Variables for authentication loop
     int i = 0;
     char *M = strdup("");  // initially empty M
     int original_x = 0;
     char Z[32] = "";
     int start_auth = 0;
     int received_M = 0;
     char *r_prime = NULL;
     
     while (i < CHlen) {
         uint8_t msgType;
         uint8_t *payload = NULL;
         uint16_t payload_len = 0;
         if (recv_message(sockfd, &msgType, &payload, &payload_len) < 0) {
             fprintf(stderr, "Failed to receive message, retrying...\n");
             continue;
         }
         if (msgType != AUTH_MSG) {
             free(payload);
             continue;
         }
         AuthMsgServer authMsg;
         if (unpack_auth_msg_server(payload, payload_len, &authMsg) < 0) {
             free(payload);
             continue;
         }
         free(payload);
         
         if (!start_auth) {
             if (strcmp(authMsg.ACK, "FF") == 0) {
                 start_auth = 1;
                 printf("Start Authenticating\n");
             }
         } else {
             // Compute expected Auth_ACK = hash_value(3, r_prime, ID_j, x_pv)
             // For the first round, r_prime may be NULL, so skip comparison.
             if (r_prime != NULL) {
                 char *Auth_ACK = hash_value(3, r_prime, ID_j, x_pv);
                 if (strcmp(authMsg.ACK, Auth_ACK) == 0) {
                     if (received_M) {
                         free(Auth_ACK);
                         // Authentication succeeded, exit loop.
                         // Free allocated fields in authMsg struct below.
                         i = CHlen; 
                         free(authMsg.ACK); free(authMsg.challenge);
                         free(authMsg.error_code); free(authMsg.OFFSET); free(authMsg.M);
                         break;
                     }
                 } else {
                     Z[0] = '\0';
                     received_M = 0;
                 }
                 free(Auth_ACK);
             }
         }
         
         // Prepare and send AUTH_MSG response
         // Instead of querying a DB, use getCRP() stub.
         const char *crp_response = getCRP();
         // In a real system, you might select one from an array.
         // Apply error correction.
         if (r_prime) free(r_prime);
         r_prime = error_correction(crp_response, authMsg.error_code);
         // Compute COM_prime = hash_value(3, r_prime, authMsg.challenge, x_pv)
         char *COM_prime = hash_value(3, r_prime, authMsg.challenge, x_pv);
         
         if (strlen(authMsg.M) > 0) {
             // Compute Z using ZXK: ZXK(M, r_prime)
             int x;
             char *Z_str = ZXK(authMsg.M, r_prime, &x);
             strncpy(Z, Z_str, sizeof(Z)-1);
             Z[sizeof(Z)-1] = '\0';
             original_x = x;
             received_M = 1;
             free(Z_str);
         }
         
         uint16_t resp_len;
         uint8_t *resp_payload = pack_auth_msg_response(HID_j, COM_prime, Z, &resp_len);
         if (send_message(sockfd, AUTH_MSG, resp_payload, resp_len) < 0) {
             perror("Send AUTH_MSG response failed");
             free(resp_payload);
             free(COM_prime);
             free(authMsg.ACK); free(authMsg.challenge);
             free(authMsg.error_code); free(authMsg.OFFSET); free(authMsg.M);
             break;
         }
         free(resp_payload);
         free(COM_prime);
         free(authMsg.ACK); free(authMsg.challenge);
         free(authMsg.error_code); free(authMsg.OFFSET); free(authMsg.M);
         i++;  // increment iteration (or adjust per your protocol)
     }
     
     // Receive final AUTH_DONE message
     uint8_t final_msgType;
     uint8_t *final_payload = NULL;
     uint16_t final_payload_len = 0;
     if (recv_message(sockfd, &final_msgType, &final_payload, &final_payload_len) < 0) {
         fprintf(stderr, "Failed to receive AUTH_DONE message\n");
         close(sockfd);
         exit(EXIT_FAILURE);
     }
     if (final_msgType == AUTH_DONE && final_payload) {
         char *MTL = unpack_auth_done(final_payload, final_payload_len);
         free(final_payload);
         // Compute Original_MTL = hash_value(2, int_to_str(original_x), M)
         char *x_str = int_to_str(original_x);
         char *Original_MTL = hash_value(2, x_str, M);
         free(x_str);
         printf("Original MTL: %s\nReceived MTL: %s\n", Original_MTL, MTL);
         if (strcmp(Original_MTL, MTL) == 0) {
             printf("Mutual Authentication Completed for %s\n", ID_j);
         } else {
             printf("MTL mismatch for %s\n", ID_j);
         }
         free(Original_MTL);
         free(MTL);
     } else {
         fprintf(stderr, "Did not receive proper AUTH_DONE message\n");
     }
     
     // Clean up
     if (r_prime) free(r_prime);
     free(M);
     free(HID_j);
     free(x_pv);
     close(sockfd);
 }
 
 int main(int argc, char *argv[]) {
     if (argc < 2) {
         printf("Usage: %s <board_number>\n", argv[0]);
         return 1;
     }
     start_prover(argv[1]);
     return 0;
 }
