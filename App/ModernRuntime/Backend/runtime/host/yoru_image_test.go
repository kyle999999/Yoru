// SPDX-License-Identifier: GPL-3.0-only
package host

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"testing"
)

func TestYoruEncodedImagePreservesSourceBytes(t *testing.T) {
	original := image.NewRGBA(image.Rect(0, 0, 3, 2))
	original.Set(1, 1, color.RGBA{255, 50, 20, 255})
	var encoded bytes.Buffer
	if err := jpeg.Encode(&encoded, original, nil); err != nil {
		t.Fatal(err)
	}
	input := append([]byte(nil), encoded.Bytes()...)
	canvas := &Canvas{Store: NewStore()}
	ref, ok := canvas.DecodeImage(input)
	if !ok {
		t.Fatal("JPEG decoding failed")
	}
	preserved, ok := canvas.Store.Fetch(ref).(*EncodedImage)
	if !ok {
		t.Fatal("original encoding was discarded")
	}
	if !bytes.Equal(preserved.Data, encoded.Bytes()) {
		t.Fatal("ImageRef.data() must preserve original JPEG bytes")
	}
	input[0] = 0
	if preserved.Data[0] != 0xFF {
		t.Fatal("image retained borrowed mutable input")
	}
	if canvas.fetchImage(ref).Bounds() != original.Bounds() {
		t.Fatal("canvas image dimensions changed")
	}
}
