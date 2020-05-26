"""
Copyright <2019> <Kazuhiro Miyahara (kazuhiro.miyahara.vs@gmail.com)>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"""

from scipy.stats import circmean
import numpy as np
from google.cloud import storage, firestore
import os
import tempfile
import cv2

storage_client = storage.Client()
PROJECT_ID = os.environ["PROJECT_ID"]
COLLECTION_NAME = os.environ["FIRESTORE_COLLECTION_NAME"]
db_client = firestore.Client()


# make binary image of suture line and get those lines as countours
def get_trace_image_contours(raw_image):
    lower_blue = np.array([95, 100, 0])
    upper_blue = np.array([145, 255, 255])
    raw_img_hsv = cv2.cvtColor(raw_image, cv2.COLOR_BGR2HSV)
    mask = cv2.inRange(raw_img_hsv, lower_blue, upper_blue)
    blur_mask = cv2.GaussianBlur(mask, (5, 5), 2.0)
    ret, th_mask = cv2.threshold(blur_mask, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    contours, hierarchy = cv2.findContours(
        th_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
    )
    return (contours, hierarchy)


# get list of length, center, direction of suture lines
def get_suture_lines_profile_list(contours):
    if not contours:
        return None

    length_list = []
    center_list = []
    direction_vec = []
    detected_lines = []

    for cnt in contours:
        (x, y), radius = cv2.minEnclosingCircle(cnt)
        data = np.array(cnt, dtype=np.float).reshape((cnt.shape[0], cnt.shape[2]))
        mean, eigvec = cv2.PCACompute(
            data, mean=np.array([], dtype=np.float), maxComponents=1
        )
        direction = eigvec[0]
        left = ((x - radius * eigvec[0][0]), (y - radius * eigvec[0][1]))
        right = ((x + radius * eigvec[0][0]), (y + radius * eigvec[0][1]))
        sut_vec = np.array([right[0] - left[0], right[1] - left[1]])
        length = np.linalg.norm(sut_vec)
        cnt_feature = {
            "center_x": x,
            "center_y": y,
            "length": length,
            "direction": direction,
        }
        detected_lines.append(cnt_feature)

    # suture lines MUST BE ALIGNED in the direction of X Axis
    detected_lines.sort(key=lambda x: x["center_x"])

    for cnt in detected_lines:
        center_list.append(np.array([cnt["center_x"], cnt["center_y"]]))
        direction_vec.append(cnt["direction"])
        length_list.append(cnt["length"])

    return (length_list, center_list, direction_vec)


# calcualte bite-cv, pitch-cv, skewness, and total-score
def get_suture_line_eval(length_list, center_list, direction_vec):
    if (not length_list) or (not center_list) or (not direction_vec):
        return None

    pitch_list = [
        np.linalg.norm(np.array([center_list[i + 1] - center_list[i]]))
        for i in range(len(center_list) - 1)
    ]

    bite_cv = np.std(length_list) / np.average(length_list)
    pitch_cv = np.std(pitch_list) / np.average(pitch_list)

    # Circular Statistics
    angle_list = [
        np.arccos(np.dot(direction_vec[i], direction_vec[i + 1]))
        for i in range(len(direction_vec) - 1)
    ]
    _circmean = circmean(angle_list)

    # Pewsey 2004
    skewness = np.sum(np.sin(2 * (angle_list - _circmean))) / len(angle_list)

    # our original definition
    total_score = np.sqrt(bite_cv ** 2 + pitch_cv ** 2 + skewness ** 2)
    return (bite_cv, pitch_cv, skewness, total_score)


def put_data_to_firestore(collection, document, data):
    doc_ref = db_client.collection(collection).document(document)
    if not data:
        return
    doc_ref.update(data)


def upload(result, file_name):
    upload_data = {
        "time": firestore.SERVER_TIMESTAMP,
        "biteCV": result[0],
        "pitchCV": result[1],
        "skewness": result[2],
        "totalScore": result[3],
    }
    put_data_to_firestore(COLLECTION_NAME, file_name, upload_data)


def eval_suture(event, context):
    file = event
    if file is None:
        return

    file_name = file["name"]
    bucket_name = file["bucket"]

    # download from cloud storage to temporary file
    blob = storage_client.bucket(bucket_name).get_blob(file_name)

    with tempfile.TemporaryDirectory() as dirname:
        tmpfile = os.path.join(dirname, "tmp")
        blob.download_to_filename(tmpfile)
        raw_img = cv2.imread(tmpfile)
        if raw_img is None:
            result = (np.nan, np.nan, np.nan, np.nan)
            upload(result, file_name)
            return

        # calulate suture line parameters
        contours, hierarchy = get_trace_image_contours(raw_img)
        if contours is None:
            result = (np.nan, np.nan, np.nan, np.nan)
            upload(result, file_name)
            return

        # vecs is a tuple (length_list, center_line, direction_vec)
        vecs = get_suture_lines_profile_list(contours)

        if vecs is None:
            result = (np.nan, np.nan, np.nan, np.nan)
        else:
            result = get_suture_line_eval(vecs[0], vecs[1], vecs[2])

        if result is None:
            result = (np.nan, np.nan, np.nan, np.nan)

        upload(result, file_name)
