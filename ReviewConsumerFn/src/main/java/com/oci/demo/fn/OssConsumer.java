package com.oci.demo.fn;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.oci.demo.review.pojo.ReviewReq;

import java.util.HashSet;
import java.util.Set;


public class OssConsumer {
    static Set<String> setOfUnpublishableWords = new HashSet<String>();
    static ObjectMapper mapper = new ObjectMapper();

    static {
        String listOfUnpublishableWords = System.getenv().get("UNPUBLISHBALE_WORD_LIST");
        System.err.println("List Of Unpublishable Words is "+ listOfUnpublishableWords);
        for(String badWord:listOfUnpublishableWords.split(",")){
            setOfUnpublishableWords.add(badWord.trim());
        }
    }

    private boolean analyseUserGeneratedContent(String reviewContent) {
        System.err.println(" In the analyseUserGeneratedContent");

        String[] listOfReviewWords = reviewContent.split(" ");
        for (String reviewWord : listOfReviewWords) {
            if (setOfUnpublishableWords.contains(reviewWord.trim())) {
                return false;
            }
        }
        return true;
    }

    public boolean handleRequest(ReviewReq msg) {
//        System.err.println(" In the consumer function " + msg);
//        ReviewReq review = null;
//        try {
//            review = mapper.readValue(msg, ReviewReq.class);
//        } catch (JsonProcessingException e) {
//            e.printStackTrace();
//        }
//        System.err.println(" In the consumer function with pojo" + review);

        boolean isItGoodReview = analyseUserGeneratedContent(msg.getReviewContent());
        System.err.println(" returning "+ isItGoodReview);
        return ObjectStorageHandler.uploadReview(isItGoodReview, msg);
    }

}