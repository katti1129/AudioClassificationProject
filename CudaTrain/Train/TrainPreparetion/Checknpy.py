import numpy as np

cm = np.load(r"C:\Users\cpsla\PycharmProjects\lab_lstm\ModelBuilding\Result\runs_crnn_fold1to4_train_eval\fold2\cm.npy")
cm_norm = np.load(r"C:\Users\cpsla\PycharmProjects\lab_lstm\ModelBuilding\Result\runs_crnn_fold1to4_train_eval\fold2\cm_norm.npy")

print("Raw CM:\n", cm)
print("Normalized CM:\n", cm_norm)
