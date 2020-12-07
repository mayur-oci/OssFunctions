package com.oci.demo.review.pojo;

import com.fasterxml.jackson.annotation.*;

import java.util.HashMap;
import java.util.Map;

@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonPropertyOrder({
        "reviewId",
        "time",
        "productId",
        "reviewContent"
})
public class ReviewReq {

    @JsonProperty("reviewId")
    private String reviewId;
    @JsonProperty("time")
    private Long time;
    @JsonProperty("productId")
    private String productId;
    @JsonProperty("reviewContent")
    private String reviewContent;
    @JsonIgnore
    private Map<String, Object> additionalProperties = new HashMap<String, Object>();

    @JsonProperty("reviewId")
    public String getReviewId() {
        return reviewId;
    }

    @JsonProperty("reviewId")
    public void setReviewId(String reviewId) {
        this.reviewId = reviewId;
    }

    @JsonProperty("time")
    public Long getTime() {
        return time;
    }

    @JsonProperty("time")
    public void setTime(Long time) {
        this.time = time;
    }

    @JsonProperty("productId")
    public String getProductId() {
        return productId;
    }

    @JsonProperty("productId")
    public void setProductId(String productId) {
        this.productId = productId;
    }

    @JsonProperty("reviewContent")
    public String getReviewContent() {
        return reviewContent;
    }

    @JsonProperty("reviewContent")
    public void setReviewContent(String reviewContent) {
        this.reviewContent = reviewContent;
    }

    @JsonAnyGetter
    public Map<String, Object> getAdditionalProperties() {
        return this.additionalProperties;
    }

    @JsonAnySetter
    public void setAdditionalProperty(String name, Object value) {
        this.additionalProperties.put(name, value);
    }

}
